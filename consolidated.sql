-- yearsem
-- lasttwosemcredit
-- enrollment clashes
-- calculate_CG

-- check_enrollment and enroll
-- propogate


CREATE OR REPLACE FUNCTION yearsem()
RETURNS RECORD
LANGUAGE PLPGSQL
AS $$
DECLARE
ret record;
ret_2 record;
a integer;
b integer;
BEGIN
select extract(year from now()) as year, extract(month from now()) as sem into ret;

if ret.sem <=6 then
ret.sem=2;
ret.year=ret.year-1;
else
ret.sem=1;
end if;
a := ret.sem;
b := ret.year;

select a, b into ret_2;

return ret_2;
END;
$$;

CREATE OR REPLACE FUNCTION lasttwosemcredit()
RETURNS real
LANGUAGE PLPGSQL
AS $$
DECLARE
last_credit real;
last2_credit real;
avg_credit real;
sem_c integer;
year_c integer;
BEGIN

select a, b from yearsem() as (a integer, b integer) into sem_c, year_c;

-- going to the prev semester courses
if sem_c=2 then
sem_c=1;
else
sem_c=2;
year_c=year_c-1;
end if;

EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_c, year_c) into last_credit;

if sem_c=2 then 
sem_c=1;
else 
sem_c=2;
year_c=year_c-1;
end if;
EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_c, year_c) into last2_credit;

if last_credit = 0 then
last_credit = 18.0;
end if;

if last2_credit = 0 then
last2_credit = 18.5;
end if;

avg_credit=(last_credit+last2_credit)/2.0;
return avg_credit;

END;
$$;

CREATE OR REPLACE FUNCTION enrollment_clashes(_courseid varchar(7))
RETURNS integer
LANGUAGE PLPGSQL
AS $$
DECLARE
ret integer:=0;
_slot integer;
BEGIN

for _slot in execute format('select slot from time_table where time_table.courseid in (select courseid from %I)',current_user||'_e')
loop
    if _slot in (select slot from time_table where time_table.courseid=_courseid) 
    then 
        raise exception 'this slot % clashes with other courses slots',_slot;
        ret:=ret+1;
    end if;
end loop;
return ret;
END;
$$;

CREATE OR REPLACE FUNCTION calculate_CG()
RETURNS real
LANGUAGE PLPGSQL
AS $$
DECLARE
ret real;
sum_c real;
RT record;
BEGIN
ret := 0.0;
sum_c := 0.0;
-- grade 0.0 is fail and not counted in CG
for RT in execute format('select * from %I where grade > 0.0', current_user || '_t') loop
sum_c := sum_c + RT.credits;
ret := ret + RT.credits * RT.grade;
end loop;
if sum_c > 0.0 then
    ret := ret / sum_c;
end if;
return ret;
END;
$$;

---------------------------------------------------------------------------------------------------
--Trigger and function

CREATE OR REPLACE FUNCTION check_enrollment()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
DECLARE
PR record;
CC record;
QR record;
creds real;
avg_last_two_sem_credit real;
this_sem_credit real;
this_course_credit real;
condn integer;
curr_CG real;
required_CG real;
batch_name varchar(8);
BEGIN
-- check if offered - ok
-- pre_req - ok
-- batch - ok
-- time-table - ok
-- cg requirement - ok
-- 1.25 rule - ok

if session_user = 'dean' or session_user = 'postgres' then
return NEW;
end if;

if (NEW.courseid, NEW.secid) not in (select courseid, secid from course_offerings) then
raise exception 'Invalid Course !!';
end if;

for PR in (select * from pre_requisite where pre_requisite.courseid =  NEW.courseid) loop
execute format('select count(*) from %I where grade >= 4.0 and courseid = %L;', current_user || '_t', PR.pre_req) into condn;
if condn = 0 then
raise exception 'Pre-requisite not satisfied !!';
end if;
end loop;

-- 2019csb1119 -> 2019csb check batch
batch_name := substr(current_user, 1, 7);
execute format('select count(*) from course_batches where course_batches.courseid = %L and course_batches.batch = %L;', NEW.courseid, batch_name) into condn;
if condn = 0 then
raise exception 'Unavailable for your batch !!';
end if;

-- timetable
select enrollment_clashes(NEW.courseid) into condn;


-- CG check part, improve
execute format('select cg from course_offerings where courseid=%L and sem=%L and year=%L and secid=%L', NEW.courseid, NEW.sem, NEW.year, NEW.secid) into required_CG;

select calculate_CG() into curr_CG;
if required_CG > curr_CG then
raise exception 'CG requirement not satisfied %', required_CG;
end if;

-- raise notice '% required CG', required_CG;

-- 1.25 rule
EXECUTE format('select sum(C) from (select courseid from %I where sem=%L and year=%L) as O, course_catalog as AB where AB.courseid=O.courseid', current_user||'_e', NEW.sem, NEW.year) into this_sem_credit;

if this_sem_credit is null then
this_sem_credit := 0;
end if;

execute format('select C from course_catalog where courseid = %L', NEW.courseid) into this_course_credit;
this_sem_credit := this_sem_credit + this_course_credit;
select lasttwosemcredit() into avg_last_two_sem_credit;
avg_last_two_sem_credit := avg_last_two_sem_credit * 1.25;
if avg_last_two_sem_credit < this_sem_credit then
raise exception '1.25 rule violated !! % % %', this_sem_credit, this_course_credit, avg_last_two_sem_credit;
end if;

-- raise exception 'success % % %', this_sem_credit, this_course_credit, avg_last_two_sem_credit;

RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION enroll(courseid varchar(7), secid integer)
RETURNS void
LANGUAGE PLPGSQL
AS $$
DECLARE
sem_c integer;
year_c integer;
BEGIN
select a, b from yearsem() as (a integer, b integer) into sem_c, year_c;
-- triggers check_enrollment
execute format('INSERT INTO %I VALUES(%L, %L, %L, %L)',  current_user || '_e', courseid, sem_c, year_c, secid);
END;
$$;

CREATE OR REPLACE FUNCTION propogate_course_enrollment()
RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER
AS $$
DECLARE
BEGIN
if session_user='dean' or session_user='postgres' then
return NEW;
end if;
execute format('insert into %I values(%L);', NEW.courseid || NEW.secid || '_e', session_user);
return NEW;
END;
$$;


CREATE OR REPLACE FUNCTION Upload_time_table(file_path varchar(400))
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
csv_path varchar(400);
BEGIN
execute format('copy %I from %L with delimiter '','' csv;', time_table, file_path);
END;
$$;

REVOKE ALL ON FUNCTION Upload_time_table FROM PUBLIC;

CREATE OR REPLACE FUNCTION load_grade_to_transcripts(_courseid varchar(7), _secid integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
jj record;
credits_now integer;
keep_track integer;
_year integer;
_sem integer;
BEGIN
/*
    Only used by dean academic section to update all the grades into the student transcript tables
*/
select a, b from yearsem() as (a integer, b integer) into _sem, _year;

select C from course_catalog where courseid = _courseid into credits_now;
keep_track := 0;
execute format('select count(*) from (select studentid from %I except select studentid from %I) as extraguys;', _courseid || _secid || '_g', _courseid || _secid || '_e') into keep_track;

if keep_track > 0 then
    raise exception 'All the grades not updated yet !!';
end if;

for jj in execute format('select * from %I;', _courseid || _secid || '_g') loop
execute format('insert into %I values(%L, %L, %L, %L, %L)', jj.studentid || '_t', _courseid, credits_now, _sem, _year, jj.grade);
end loop;

END;
$$;

REVOKE ALL ON FUNCTION load_grade_to_transcripts FROM PUBLIC;

CREATE OR REPLACE FUNCTION load_grade(courseid varchar(7), secid integer, file_name varchar(1000))
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
csv_path varchar(50);
keep_track integer;
BEGIN
-- change security to Everyone
execute format('select count(*) from instructor_info where teacherid=%L and courseid=%L', session_user, courseid) into keep_track;
if keep_track = 0 then
    raise exception 'access denied';
end if;
csv_path := 'C:\Users\Hp\Downloads\' || file_name || '.csv';
execute format('copy %I from %L with delimiter '','' csv;', courseid || secid || '_g', csv_path);
END;
$$;

REVOKE ALL ON FUNCTION load_grade FROM PUBLIC;


-- CREATE TRIGGER whatever_t
-- AFTER INSERT
-- ON studentid_e
-- FOR EACH ROW
-- EXECUTE PROCEDURE propogate_course_enrollment();

--------------------------------------------------------------------------------------------------------

create table dean_h(
courseid varchar(7),
sem integer not null,
year integer not null,
status varchar(50) not null,
ins_status varchar(50) not null,
ba_status varchar(50) not null,
secid integer not null,
entry_no varchar(12),
primary key(courseid, entry_no)
);

CREATE OR REPLACE FUNCTION make_ticket(courseid varchar(7), secid integer)
RETURNS void
LANGUAGE PLPGSQL
AS $$
DECLARE
year_c integer;
sem_c integer;
BEGIN

select a, b from yearsem() as (a integer, b integer) into sem_c, year_c;
execute format('INSERT INTO %I VALUES(%L,%L,%L,%L,%L);',  session_user || '_h', courseid, sem_c, secid, year_c, 'ticket pending');
END;
$$;

CREATE OR REPLACE FUNCTION student_request()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
DECLARE
PR record;
CC record;
QR record;
creds real;
avg_last_two_sem_credit real;
this_sem_credit real;
this_course_credit real;
condn integer;
curr_CG real;
required_CG real;
batch_name varchar(8);
BEGIN
-- check if offered - ok
-- pre_req - ok
-- batch - ok
-- time-table - ok
-- cg requirement - ok
-- 1.25 rule - ok

if (NEW.courseid, NEW.secid) not in (select courseid, secid from course_offerings) then
raise exception 'Invalid Course !!';
end if;

for PR in (select * from pre_requisite where pre_requisite.courseid =  NEW.courseid) loop
execute format('select count(*) from %I where grade >= 4.0 and courseid = %L;', current_user || '_t', PR.pre_req) into condn;
if condn = 0 then
raise exception 'Pre-requisite not satisfied !!';
end if;
end loop;

-- check batch
batch_name := substr(current_user, 1, 7);
execute format('select count(*) from course_batches where course_batches.courseid = %L and course_batches.batch = %L;', NEW.courseid, batch_name) into condn;
if condn = 0 then
raise exception 'Unavailable for your batch !!';
end if;

-- timetable
select enrollment_clashes(NEW.courseid) into condn;


-- CG check part, improve
execute format('select cg from course_offerings where courseid=%L and sem=%L and year=%L and secid=%L', NEW.courseid, NEW.sem, NEW.year, NEW.secid) into required_CG;

select calculate_CG() into curr_CG;
if required_CG > curr_CG then
raise exception 'CG requirement not satisfied %', required_CG;
end if;

-- 1.25 rule
EXECUTE format('select sum(C) from (select courseid from %I where sem=%L and year=%L) as O, course_catalog as AB where AB.courseid=O.courseid', current_user||'_e', NEW.sem, NEW.year) into this_sem_credit;

if this_sem_credit is null then
this_sem_credit := 0;
end if;

execute format('select C from course_catalog where courseid = %L', NEW.courseid) into this_course_credit;
this_sem_credit := this_sem_credit + this_course_credit;
select lasttwosemcredit() into avg_last_two_sem_credit;
avg_last_two_sem_credit := avg_last_two_sem_credit * 1.25;
if avg_last_two_sem_credit > this_sem_credit then
raise exception '1.25 rule not violated, no need to raise a ticket !!';
end if;

raise notice '1.25 rule status % %', avg_last_two_sem_credit, this_sem_credit;

RETURN NEW;
END;
$$;

create or replace function student_request_later()
returns TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER
AS $$
DECLARE
_teacherid integer;
BEGIN
-- assumption of only one instructor with one courseid and secid
execute format('select teacherid from course_offerings where courseid=%L and secid=%L', NEW.courseid, NEW.secid) into _teacherid;
execute format('INSERT INTO %I VALUES(%L,%L,%L,%L,%L,%L);',  _teacherid || '_h', NEW.courseid, NEW.sem, NEW.year, 'NA', NEW.secid, session_user);
return NEW;
END;
$$;

---------------------------------------------------

CREATE OR REPLACE FUNCTION approve_teacher(studentid varchar(12), course varchar(7), approval varchar(3))
RETURNS void
LANGUAGE PLPGSQL
AS $$
BEGIN
execute format('UPDATE %I SET status=%L where entry_no=%L and courseid=%L;', session_user || '_h', approval, studentid, course);
END;
$$;

CREATE OR REPLACE FUNCTION teacher_request()
RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER
AS $$
DECLARE
batchadvisor varchar(8);
BEGIN

batchadvisor := substr(NEW.entry_no, 1, 7);
execute format('INSERT INTO %I VALUES(%L,%L,%L,%L,%L,%L,%L);',  batchadvisor || '_h', NEW.courseid, NEW.sem, NEW.year, 'NA', NEW.status, NEW.secid, NEW.entry_no);

return NEW;
END;
$$;

--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION approve_ba(studentid varchar(12), course varchar(7), approval varchar(3))
RETURNS void
LANGUAGE PLPGSQL
AS $$
BEGIN
execute format('UPDATE %I SET status=%L where entry_no=%L and courseid=%L;', session_user || '_h', approval, studentid, course);
END;
$$;

CREATE OR REPLACE FUNCTION batch_advisor_request()
RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER
AS $$
DECLARE
-- _teacherid integer;
batchadvisor varchar(7);
BEGIN

batchadvisor := substr(NEW.entry_no, 1, 7);
execute format('INSERT INTO %I VALUES(%L,%L,%L,%L,%L,%L,%L,%L);',  'dean' || '_h', NEW.courseid, NEW.sem, NEW.year, 'NA', NEW.ins_status, NEW.status, NEW.secid, NEW.entry_no);

return NEW;
END;
$$;

-------------------------------------------------

CREATE OR REPLACE FUNCTION approve_dean(studentid varchar(12), course varchar(7), approval varchar(3))
RETURNS void
LANGUAGE PLPGSQL
AS $$
BEGIN
execute format('UPDATE %I SET status=%L WHERE courseid=%L and entry_no=%L;', 'dean_h', approval, course, studentid);
END;
$$;

CREATE OR REPLACE FUNCTION to_dean_request()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$

BEGIN

if NEW.status='Y' then
-- dean approved
execute format('UPDATE %I SET status=%L WHERE courseid=%L;',  NEW.entry_no || '_h', 'enrolled', NEW.courseid);
-- also insert this into enrollment table
execute format('INSERT INTO %I values(%L, %L, %L, %L);', NEW.entry_no || '_e', NEW.courseid, NEW.sem, NEW.year, NEW.secid);
execute format('INSERT into %I values(%L);', NEW.courseid || NEW.secid || '_e', NEW.entry_no);
ELSIF NEW.status='N' then

execute format('UPDATE %I SET status=%L WHERE courseid=%L;',  NEW.entry_no || '_h', 'dean declined', NEW.courseid);

END IF;

return NEW;
END;
$$;

CREATE TRIGGER final_dean_request
AFTER UPDATE
ON dean_h
FOR EACH ROW
EXECUTE PROCEDURE to_dean_request();

---------------------------------------------
create user dean with password 'imdean';

GRANT EXECUTE ON FUNCTION Upload_time_table TO dean;
GRANT EXECUTE ON FUNCTION load_grade_to_transcripts TO dean;
grant select, update on dean_h to dean;

-- student info
create table student_info(
    studentid varchar(12) primary key,
    _name varchar(50) not null,
    dept_name varchar(20) not null
);

CREATE OR REPLACE FUNCTION create_student()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
EXECUTE format('CREATE USER %I WITH PASSWORD ''123''', NEW.studentid);
-- Transcript table
EXECUTE format('CREATE TABLE %I (
    courseid varchar(7) primary key,
    credits real not null,
    sem integer not null,
    year integer not null,
    grade integer not null
    );', NEW.studentid || '_t');
-- Enrolled table
EXECUTE format('CREATE TABLE %I (
    courseid varchar(7),
    sem integer not null,
    year integer not null,
    secid integer not null,
    primary key(courseid, sem, year)
    );', NEW.studentid || '_e');
-- History/Request table
EXECUTE format('CREATE TABLE %I (
    courseid varchar(7) primary key,
    sem integer not null,
    secid integer,
    year integer not null,
    status varchar(50) not null
    );', NEW.studentid || '_h');

EXECUTE format('CREATE TRIGGER %I
BEFORE INSERT
ON %I
FOR EACH ROW
EXECUTE PROCEDURE check_enrollment();',
'check_enroll_' || NEW.studentid || '_e_t',
NEW.studentid || '_e'
);

EXECUTE format('CREATE TRIGGER %I
AFTER INSERT
ON %I
FOR EACH ROW
EXECUTE PROCEDURE propogate_course_enrollment();',
'enrolled_' || NEW.studentid || '_e_t',
NEW.studentid || '_e'
);

EXECUTE format('CREATE TRIGGER %I
BEFORE INSERT
ON %I
FOR EACH ROW
EXECUTE PROCEDURE student_request();',
'ticket_gen' || NEW.studentid || '_h_t',
NEW.studentid || '_h'
);

EXECUTE format('CREATE TRIGGER %I
AFTER INSERT
ON %I
FOR EACH ROW
EXECUTE PROCEDURE student_request_later();',
'ticket_generated' || NEW.studentid || '_h_t',
NEW.studentid || '_h'
);

execute format('grant select on %I to %I;', NEW.studentid || '_t', NEW.studentid);
execute format('grant select, insert on %I, %I to %I;', NEW.studentid || '_h', NEW.studentid || '_e', NEW.studentid);
execute format('grant select, insert, update on %I, %I to dean;', NEW.studentid || '_e', NEW.studentid || '_t');
execute format('grant select, update on %I to dean;', NEW.studentid || '_h');
return NEW;
END;
$$;

CREATE TRIGGER student_info_t
BEFORE INSERT
ON student_info
FOR EACH ROW
EXECUTE PROCEDURE create_student();

insert into student_info values('2019csb1072', 'Name Surname', 'CSE');
insert into student_info values('2019eeb1063', 'Nice Guy', 'EE');
insert into student_info values('2019meb1214', 'Another Guy', 'ME');
insert into student_info values('2019mmb1372', 'Random guy', 'MM');
insert into student_info values('2019mcb1141', 'Another One', 'MNC');
insert into student_info values('2019chb1217', 'Guy Random', 'CH');
insert into student_info values('2019ceb1319', 'Guy Random', 'CE');

--------------------------------------------------------------------------------------------------------
-- instructor info

create table instructor_info(
    teacherid integer,
    _name varchar(50) not null,
    dept_name varchar(20) not null,
    courseid varchar(7),
    secid integer,
    primary key(courseid, secid)
);

CREATE OR REPLACE FUNCTION create_instructors()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN

if NEW.teacherid in (select teacherid from instructor_info) then
return NEW;
end if;

execute format('create user %I with password ''123'';', NEW.teacherid);

execute format('CREATE TABLE IF NOT EXISTS %I (courseid varchar(7),
sem integer not null,
year integer not null,
status varchar(50) not null,
secid integer not null,
entry_no varchar(12),
primary key(courseid, entry_no));', NEW.teacherid || '_h');

execute format('CREATE TRIGGER %I
AFTER UPDATE
ON %I
FOR EACH ROW
EXECUTE PROCEDURE teacher_request();',
'move_req_' || NEW.teacherid || '_h_t', NEW.teacherid || '_h');

execute format('GRANT SELECT, UPDATE on %I to %I;', NEW.teacherid || '_h', NEW.teacherid);
execute format('GRANT EXECUTE ON FUNCTION load_grade TO %I;', NEW.teacherid);

return NEW;
END;
$$;

CREATE TRIGGER instructor_info_t
BEFORE INSERT
ON instructor_info
FOR EACH ROW
EXECUTE PROCEDURE create_instructors();

insert into instructor_info values(92, 'Teacher Person', 'CSE', 'cs303', 1);
insert into instructor_info values(91, 'Person Person', 'CSE', 'cs301', 1);
insert into instructor_info values(93, 'Person Teacher', 'MATH', 'cs302', 1);

--------------------------------------------------------------------------------------------------------
-- BA info

create table ba_info(
    batchadvisorid varchar(8),
    teacherid integer,
    primary key(batchadvisorid)
);

CREATE OR REPLACE FUNCTION create_ba()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN

execute format('create user %I with password ''123'';', NEW.batchadvisorid);

execute format('create table %I (
courseid varchar(7),
sem integer not null,
year integer not null,
status varchar(50) not null,
ins_status varchar(50) not null,
secid integer not null,
entry_no varchar(12),
primary key(courseid, entry_no)
);', NEW.batchadvisorid || '_h');

execute format('CREATE TRIGGER %I
AFTER UPDATE
ON %I
FOR EACH ROW
EXECUTE PROCEDURE batch_advisor_request();', 'to_dean_' || NEW.batchadvisorid || '_h_t', NEW.batchadvisorid || '_h');

execute format('GRANT SELECT, UPDATE on %I to %I;', NEW.batchadvisorid || '_h', NEW.batchadvisorid);

return NEW;
END;
$$;

CREATE TRIGGER ba_info_t
BEFORE INSERT
ON ba_info
FOR EACH ROW
EXECUTE PROCEDURE create_ba();


insert into ba_info values('2019csb', 15);
insert into ba_info values('2019meb', 16);
insert into ba_info values('2019mcb', 17);
insert into ba_info values('2019mmb', 18);
insert into ba_info values('2019eeb', 19);
insert into ba_info values('2019chb', 20);
insert into ba_info values('2019ceb', 21);

---------------------------------------------------------------------------------------------------------

create table course_catalog(
courseid varchar(7) primary key,
L real not null,
T real not null,
P real not null,
S real not null,
C real not null
);

insert into course_catalog values('cs301', 3, 1, 2, 6, 4);
insert into course_catalog values('cs303', 3, 1, 2, 6, 4);
insert into course_catalog values('cs201', 3, 1, 2, 6, 4);
insert into course_catalog values('cs203', 3, 1, 3, 6, 4);
insert into course_catalog values('cs202', 3, 1, 2, 6, 4);
insert into course_catalog values('cs204', 3, 1, 2, 6, 4);
insert into course_catalog values('ge103', 3, 0, 3, 7.5, 4.5);
insert into course_catalog values('cs101', 3, 1, 0, 5, 3);
insert into course_catalog values('ma101', 3, 1, 0, 5, 3);
insert into course_catalog values('cs302', 3, 1, 0, 5, 3);
insert into course_catalog values('cs304', 4, 1, 0, 5, 4);

select * from course_catalog;

create table pre_requisite(
courseid varchar(7) not null,
pre_req varchar(7) not null
);

insert into pre_requisite values('cs201', 'ge103');
insert into pre_requisite values('cs202', 'cs201');
insert into pre_requisite values('cs204', 'cs203');
insert into pre_requisite values('cs301', 'cs201');
insert into pre_requisite values('cs302', 'cs202');
insert into pre_requisite values('cs303', 'cs203');

select * from pre_requisite;

create table course_offerings(
courseid varchar(7) not null,
teacherid integer not null,
secid integer not null,
sem integer not null,
year integer not null,
cg real,
primary key(courseid, secid)
);

CREATE OR REPLACE FUNCTION create_course_sec_table()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
DECLARE
present_course integer;
BEGIN

EXECUTE format('select count(*) from course_catalog where courseid=%L', NEW.courseid) into present_course;
if present_course = 0 then
    raise exception 'course not present in course catalog';
end if;

-- we will create course grade as well as course enrollment table (any one can view the enrollment table as in aims)
EXECUTE format('CREATE TABLE %I (studentid varchar(12));', NEW.courseid || NEW.secid || '_e');
EXECUTE format('CREATE TABLE %I (studentid varchar(12) primary key, grade integer);', NEW.courseid || NEW.secid || '_g');

execute format('GRANT select, insert, update on %I to %I;', NEW.courseid || NEW.secid || '_g', NEW.teacherid);
execute format('GRANT select on %I to PUBLIC;', NEW.courseid || NEW.secid || '_e');
execute format('GRANT select on %I to dean', NEW.courseid || NEW.secid || '_g');
execute format('GRANT select, insert, update on %I to dean', NEW.courseid || NEW.secid || '_e');

RETURN NEW;
END;
$$;

CREATE TRIGGER insert_course_offering
BEFORE INSERT
ON course_offerings
FOR EACH ROW
EXECUTE PROCEDURE create_course_sec_table();

-- course, teacherid, sec, sem, yr, cg
insert into course_offerings values('cs301', 91, 1, 1, 2021, 7.5);
insert into course_offerings values('cs302', 93, 1, 1, 2021, 0.0);
insert into course_offerings values('cs303', 92, 1, 1, 2021, 0.0);
insert into course_offerings values('cs304', 92, 1, 1, 2021, 7.0);

CREATE TABLE time_table(
    courseid varchar(7) not null,
    slot integer not null,
    PRIMARY KEY(courseid,slot)
);

insert into time_table values('cs301',11);
insert into time_table values('cs301',12);
insert into time_table values('cs301',13);
insert into time_table values('cs301',14);

insert into time_table values('cs303',15);
insert into time_table values('cs303',16);
insert into time_table values('cs303',17);
insert into time_table values('cs303',18);

insert into time_table values('cs201',19);
insert into time_table values('cs201',21);
insert into time_table values('cs201',22);
insert into time_table values('cs201',23);

insert into time_table values('cs203',24);
insert into time_table values('cs203',25);
insert into time_table values('cs203',26);
insert into time_table values('cs203',27);

insert into time_table values('cs202',11);
insert into time_table values('cs202',28);
insert into time_table values('cs202',29);
insert into time_table values('cs202',30);

insert into time_table values('cs204',31);
insert into time_table values('cs204',32);
insert into time_table values('cs204',33);
insert into time_table values('cs204',34);

insert into time_table values('ge103',31);
insert into time_table values('ge103',35);
insert into time_table values('ge103',36);

insert into time_table values('cs101',37);
insert into time_table values('cs101',38);
insert into time_table values('cs101',39);
insert into time_table values('cs101',40);

insert into time_table values('ma101',41);
insert into time_table values('ma101',42);
insert into time_table values('ma101',43);
insert into time_table values('ma101',44);

insert into time_table values('cs302',45);
insert into time_table values('cs302',46);
insert into time_table values('cs302',47);
insert into time_table values('cs302',48);

insert into time_table values('cs304',45);
insert into time_table values('cs304',46);
insert into time_table values('cs304',47);
insert into time_table values('cs304',48);

CREATE TABLE slot_time(
    slotid integer primary key,
    day integer not null,
    slot integer not null,
    time_s varchar(50) not null
);

insert into slot_time values(11, 1, 1, '9:00 am - 9:50 am');
insert into slot_time values(12, 1, 2, '10:00 am - 10:50 am');
insert into slot_time values(13, 1, 3, '11:00 am - 11:50 am');
insert into slot_time values(14, 1, 4, '12:00 pm - 12:50 pm');
insert into slot_time values(15, 1, 5, '2:00 pm - 2:50 pm');
insert into slot_time values(16, 1, 6, '3:00 pm - 3:50 pm');
insert into slot_time values(17, 1, 7, '4:00 pm - 4:50 pm');
insert into slot_time values(18, 1, 8, '5:00 pm - 5:50 pm');
insert into slot_time values(19, 1, 9, '6:00 pm - 6:50 pm');

insert into slot_time values(21, 2, 1, '9:00 am - 9:50 am');
insert into slot_time values(22, 2, 2, '10:00 am - 10:50 am');
insert into slot_time values(23, 2, 3, '11:00 am - 11:50 am');
insert into slot_time values(24, 2, 4, '12:00 pm - 12:50 pm');
insert into slot_time values(25, 2, 5, '2:00 pm - 2:50 pm');
insert into slot_time values(26, 2, 6, '3:00 pm - 3:50 pm');
insert into slot_time values(27, 2, 7, '4:00 pm - 4:50 pm');
insert into slot_time values(28, 2, 8, '5:00 pm - 5:50 pm');
insert into slot_time values(29, 2, 9, '6:00 pm - 6:50 pm');

insert into slot_time values(31, 3, 1, '9:00 am - 9:50 am');
insert into slot_time values(32, 3, 2, '10:00 am - 10:50 am');
insert into slot_time values(33, 3, 3, '11:00 am - 11:50 am');
insert into slot_time values(34, 3, 4, '12:00 pm - 12:50 pm');
insert into slot_time values(35, 3, 5, '2:00 pm - 2:50 pm');
insert into slot_time values(36, 3, 6, '3:00 pm - 3:50 pm');
insert into slot_time values(37, 3, 7, '4:00 pm - 4:50 pm');
insert into slot_time values(38, 3, 8, '5:00 pm - 5:50 pm');
insert into slot_time values(39, 3, 9, '6:00 pm - 6:50 pm');

insert into slot_time values(41, 4, 1, '9:00 am - 9:50 am');
insert into slot_time values(42, 4, 2, '10:00 am - 10:50 am');
insert into slot_time values(43, 4, 3, '11:00 am - 11:50 am');
insert into slot_time values(44, 4, 4, '12:00 pm - 12:50 pm');
insert into slot_time values(45, 4, 5, '2:00 pm - 2:50 pm');
insert into slot_time values(46, 4, 6, '3:00 pm - 3:50 pm');
insert into slot_time values(47, 4, 7, '4:00 pm - 4:50 pm');
insert into slot_time values(48, 4, 8, '5:00 pm - 5:50 pm');
insert into slot_time values(49, 4, 9, '6:00 pm - 6:50 pm');

insert into slot_time values(51, 5, 1, '9:00 am - 9:50 am');
insert into slot_time values(52, 5, 2, '10:00 am - 10:50 am');
insert into slot_time values(53, 5, 3, '11:00 am - 11:50 am');
insert into slot_time values(54, 5, 4, '12:00 pm - 12:50 pm');
insert into slot_time values(55, 5, 5, '2:00 pm - 2:50 pm');
insert into slot_time values(56, 5, 6, '3:00 pm - 3:50 pm');
insert into slot_time values(57, 5, 7, '4:00 pm - 4:50 pm');
insert into slot_time values(58, 5, 8, '5:00 pm - 5:50 pm');
insert into slot_time values(59, 5, 9, '6:00 pm - 6:50 pm');

CREATE TABLE course_batches(
    courseid varchar(7) not null,
    secid integer not null,
    sem integer not null,
    year integer not null,
    batch varchar(10) not null
);

insert into course_batches values('ma101', 1, 1, 2021, '2021csb');
insert into course_batches values('ma101', 2, 1, 2021, '2021csb');
insert into course_batches values('ma101', 1, 1, 2021, '2021mnc');
insert into course_batches values('ma101', 2, 1, 2021, '2021mnc');
insert into course_batches values('ma101', 1, 1, 2021, '2021mcb');
insert into course_batches values('ma101', 2, 1, 2021, '2021mcb');
insert into course_batches values('ma101', 1, 1, 2021, '2021med');
insert into course_batches values('ma101', 2, 1, 2021, '2021med');
insert into course_batches values('ma101', 1, 1, 2021, '2021mmb');
insert into course_batches values('ma101', 2, 1, 2021, '2021mmb');

insert into course_batches values('ge103', 1, 1, 2021, '2021csb');
insert into course_batches values('ge103', 2, 1, 2021, '2021csb');
insert into course_batches values('ge103', 1, 1, 2021, '2021mcb');
insert into course_batches values('ge103', 2, 1, 2021, '2021mcb');
insert into course_batches values('ge103', 1, 1, 2021, '2021meb');
insert into course_batches values('ge103', 2, 1, 2021, '2021meb');
insert into course_batches values('ge103', 1, 1, 2021, '2021med');
insert into course_batches values('ge103', 2, 1, 2021, '2021med');
insert into course_batches values('ge103', 1, 1, 2021, '2021mmb');
insert into course_batches values('ge103', 2, 1, 2021, '2021mmb');

insert into course_batches values('cs101', 1, 1, 2021, '2021csb');
insert into course_batches values('cs101', 1, 1, 2021, '2021mcb');

insert into course_batches values('cs201', 1, 1, 2021, '2020csb');
insert into course_batches values('cs203', 1, 1, 2021, '2020csb');
insert into course_batches values('cs201', 1, 1, 2021, '2020mcb');
insert into course_batches values('cs203', 1, 1, 2021, '2020mcb');
insert into course_batches values('cs202', 1, 2, 2021, '2020csb');
insert into course_batches values('cs204', 1, 2, 2021, '2020csb');
insert into course_batches values('cs202', 1, 2, 2021, '2020mcb');
insert into course_batches values('cs204', 1, 2, 2021, '2020mcb');

insert into course_batches values('cs301', 1, 1, 2021, '2019csb');
insert into course_batches values('cs301', 1, 1, 2021, '2019mcb');
insert into course_batches values('cs302', 1, 1, 2021, '2019csb');
insert into course_batches values('cs302', 1, 1, 2021, '2019mcb');
insert into course_batches values('cs303', 1, 1, 2021, '2019csb');
insert into course_batches values('cs303', 1, 1, 2021, '2019mcb');
insert into course_batches values('cs301', 1, 1, 2021, '2019meb');
insert into course_batches values('cs301', 1, 1, 2021, '2019mmb');
insert into course_batches values('cs301', 1, 1, 2021, '2019eeb');
insert into course_batches values('cs302', 1, 1, 2021, '2019chb');
insert into course_batches values('cs302', 1, 1, 2021, '2019ceb');
insert into course_batches values('cs302', 1, 1, 2021, '2019eeb');
insert into course_batches values('cs303', 1, 1, 2021, '2019chb');
insert into course_batches values('cs303', 1, 1, 2021, '2019mcb');
insert into course_batches values('cs303', 1, 1, 2021, '2019meb');
insert into course_batches values('cs303', 1, 1, 2021, '2019eeb');
insert into course_batches values('cs304', 1, 1, 2021, '2019chb');
insert into course_batches values('cs304', 1, 1, 2021, '2019mcb');
insert into course_batches values('cs304', 1, 1, 2021, '2019meb');
insert into course_batches values('cs304', 1, 1, 2021, '2019eeb');
insert into course_batches values('cs304', 1, 1, 2021, '2019csb');

grant select on student_info, instructor_info, ba_info, course_catalog, course_offerings, pre_requisite, course_batches, time_table to PUBLIC;

insert into "2019csb1072_t" values ('ma101', 3, 1, 2019, 7);
insert into "2019csb1072_t" values ('ge103', 4.5, 1, 2019, 6);
insert into "2019csb1072_t" values ('ns101', 1, 1, 2019, 10);
insert into "2019csb1072_t" values ('cs101', 3, 2, 2019, 8);
insert into "2019csb1072_t" values ('ma102', 3, 2, 2019, 8);
insert into "2019csb1072_t" values ('ma102', 3, 2, 2019, 8);
insert into "2019csb1072_t" values ('ns102', 1, 2, 2019, 10);
insert into "2019csb1072_t" values ('cs201', 4, 1, 2020, 6);
insert into "2019csb1072_t" values ('cs203', 4, 1, 2020, 8);
insert into "2019csb1072_t" values ('cs202', 4, 2, 2020, 8);
insert into "2019csb1072_t" values ('cs204', 4, 2, 2020, 8);

insert into "2019eeb1063_t" values ('ma101', 3, 1, 2019, 7);
insert into "2019eeb1063_t" values ('ge103',  4.5, 1, 2019, 8);
insert into "2019eeb1063_t" values ('ns101', 1, 1, 2019, 10);
insert into "2019eeb1063_t" values ('cs101', 3, 2, 2019, 7);
insert into "2019eeb1063_t" values ('ma102', 3, 2, 2019, 8);
insert into "2019eeb1063_t" values ('ma102', 3, 2, 2019, 9);
insert into "2019eeb1063_t" values ('ns102', 1, 2, 2019, 9);
insert into "2019eeb1063_t" values ('cs201', 4, 1, 2020, 9);
insert into "2019eeb1063_t" values ('cs203', 4, 1, 2020, 9);
insert into "2019eeb1063_t" values ('cs202', 4, 2, 2020, 7);
insert into "2019eeb1063_t" values ('cs204', 4, 2, 2020, 9);

insert into "2019meb1214_t" values('cs101', 3, 2, 2019, 9);
insert into "2019meb1214_t" values('ge103', 4.5, 1, 2019, 9);
insert into "2019meb1214_t" values('cs201', 4, 1, 2020, 9);
insert into "2019meb1214_t" values('cs203', 4, 1, 2020, 9);
insert into "2019meb1214_t" values('cs202', 4, 2, 2020, 8);
insert into "2019meb1214_t" values('cs204', 4, 2, 2020, 10);
insert into "2019mmb1372_t" values ('ma101', 3, 1, 2019, 5);
insert into "2019mmb1372_t" values ('ge103', 4.5, 1, 2019, 4);
insert into "2019mmb1372_t" values ('ns101', 1, 1, 2019, 5);

insert into "2019mmb1372_t" values ('cs101', 3, 2, 2019, 5);
insert into "2019mmb1372_t" values ('ma102', 3, 2, 2019, 4);
insert into "2019mmb1372_t" values ('ma102', 3, 2, 2019, 4);
insert into "2019mmb1372_t" values ('ns102', 1, 2, 2019, 4);

insert into "2019mmb1372_t" values ('cs201', 4, 1, 2020, 0);
insert into "2019mmb1372_t" values ('cs203', 4, 1, 2020, 4);

insert into "2019mmb1372_t" values ('cs202', 4, 2, 2020, 5);
insert into "2019mmb1372_t" values ('cs204', 4, 2, 2020, 4);

insert into "2019mcb1141_t" values ('ma101', 3, 1, 2019, 4);
insert into "2019mcb1141_t" values ('ge103', 4.5, 1, 2019, 4);
insert into "2019mcb1141_t" values ('ns101', 1, 1, 2019, 5);

insert into "2019mcb1141_t" values ('cs101', 3, 2, 2019, 4);
insert into "2019mcb1141_t" values ('ma102', 3, 2, 2019, 4);
insert into "2019mcb1141_t" values ('ma102', 3, 2, 2019, 5);
insert into "2019mcb1141_t" values ('ns102', 1, 2, 2019, 4);

insert into "2019mcb1141_t" values ('cs201', 4, 1, 2020, 5);
insert into "2019mcb1141_t" values ('cs203', 4, 1, 2020, 4);

insert into "2019mcb1141_t" values ('cs202', 4, 2, 2020, 4);
insert into "2019mcb1141_t" values ('cs204', 4, 2, 2020, 5);


insert into "2019chb1217_t" values ('ma101', 3, 1, 2019, 7);
insert into "2019chb1217_t" values ('ge103', 4.5, 1, 2019, 8);
insert into "2019chb1217_t" values ('ns101', 1, 1, 2019, 7);

insert into "2019chb1217_t" values ('cs101', 3, 2, 2019, 7);
insert into "2019chb1217_t" values ('ma102', 3, 2, 2019, 8);
insert into "2019chb1217_t" values ('ma102', 3, 2, 2019, 7);
insert into "2019chb1217_t" values ('ns102', 1, 2, 2019, 6);

insert into "2019chb1217_t" values ('cs201', 4, 1, 2020, 8);
insert into "2019chb1217_t" values ('cs203', 4, 1, 2020, 7);

insert into "2019chb1217_t" values ('cs202', 4, 2, 2020, 8);
insert into "2019chb1217_t" values ('cs204', 4, 2, 2020, 7);


insert into "2019ceb1319_t" values ('ma101', 3, 1, 2019, 7);
insert into "2019ceb1319_t" values ('ge103', 4.5, 1, 2019, 8);
insert into "2019ceb1319_t" values ('ns101', 1, 1, 2019, 7);

insert into "2019ceb1319_t" values ('cs101', 3, 2, 2019, 7);
insert into "2019ceb1319_t" values ('ma102', 3, 2, 2019, 8);
insert into "2019ceb1319_t" values ('ma102', 3, 2, 2019, 7);
insert into "2019ceb1319_t" values ('ns102', 1, 2, 2019, 6);

insert into "2019ceb1319_t" values ('cs201', 4, 1, 2020, 8);
insert into "2019ceb1319_t" values ('cs203', 4, 1, 2020, 7);

insert into "2019ceb1319_t" values ('cs202', 4, 2, 2020, 8);
insert into "2019ceb1319_t" values ('cs204', 4, 2, 2020, 7);

grant select, insert, update, delete on time_table, course_batches, course_offerings, course_catalog, student_info, instructor_info, ba_info, pre_requisite to dean;

----------------------------------------------------------------------------------------------------------


CREATE OR REPLACE FUNCTION semsg(studentid varchar(12),sem_a integer, year_a integer)
RETURNS real
LANGUAGE PLPGSQL
AS $$
DECLARE
sg real;
num real;
den real;
BEGIN

EXECUTE format('select sum(grade * credits) from %I where sem=%L and year=%L;', studentid||'_t', sem_a, year_a) into num;
EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', studentid||'_t', sem_a, year_a) into den;

if den > 0.0 then
sg := num / den;
end if;

return sg;

END;
$$;


CREATE OR REPLACE FUNCTION generate_transcripts(studentid varchar(12),_sem integer, _year integer)
RETURNS table(
    courseid varchar(12),
    credits real,
    sem int,
    year int,
    grade int
    )
LANGUAGE plpgsql
AS $$
DECLARE
i record;
ret real;
sum_c real;
RT record;
BEGIN
raise notice '% %',_sem,_year;
if(_sem=0 and _year=0) then 
        ret := 0.0;
        sum_c := 0.0;
        -- grade = 0.0 is fail and not counted in CG
        for RT in execute format('select * from %I where grade > 0.0', studentid || '_t') loop
        sum_c := sum_c + RT.credits;
        ret := ret + RT.credits * RT.grade;
        end loop;
        
        if sum_c > 0.0 then
        ret := ret / sum_c;
        end if;

        raise notice 'The current CGPA of % is %', studentid, ret;
        return query execute format('select courseid,credits,sem,year,grade from %I',studentid||'_t');
else
        ret := semsg(studentid, _sem, _year);
        raise notice 'The SG of % in % sem and % year is %', studentid, _sem , _year, ret;
        return query execute format('select courseid,credits,sem,year,grade from %I where sem=%L and year=%L',studentid||'_t',_sem,_year);

end if;


END;
$$;