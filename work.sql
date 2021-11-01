
/*
CREATE OR REPLACE FUNCTION ac()
RETURNS void
LANGUAGE PLPGSQL security definer
AS $$
BEGIN
insert into nn1 values(10);
raise notice 'user %', session_user;
END;
$$;

SELECT 'DROP FUNCTION' || oid::regprocedure
FROM   pg_proc
WHERE  proname = 'my_function_name'  -- name without schema-qualification
AND    pg_function_is_visible(oid);  -- restrict to current search_path

GRANT ALL ON PROCEDURE load_grade TO ab;

CREATE OR REPLACE FUNCTION nicenice(courseid varchar(7))
RETURNS TABLE(
    pre_req varchar(7)
)
LANGUAGE PLPGSQL
AS $$
BEGIN
return query EXECUTE format('select pre_req from pre_requisite where pre_requisite.courseid = %L;', courseid);
END;
$$;
*/

-- Enroll ?
-- Course enrollment table 
-- 

-- Student
-- Transcript table, Enrolled table, Request/History table (only when 1.25 rule breaks)

-- Teacher
-- Enrolled table, Grade table, REQUEST

-- BA
-- REQUEST

-- DEAN
-- REQUEST + extra

-- Student tables exists
-- Triggers
-- Enroll, History

-- xyz(course); -> (current_user)
--(2019CSB1119_T), (2019CSB1119_E), ...

CREATE TABLE postgres_e(
    courseid varchar(7) primary key
);

CREATE OR REPLACE FUNCTION enroll(courseid varchar(7))
RETURNS void
LANGUAGE PLPGSQL
AS $$
DECLARE
ret record;
BEGIN
select yearsem() into ret;
execute format('INSERT INTO %I VALUES(%L, %L, %L)',  current_user || '_e', courseid, ret.year, ret.sem);
END;
$$;

-- sg=summation(credit*grade)/sumattion(credit) for each courses in that sem,year
CREATE OR REPLACE FUNCTION semsg(sem_a integer, year_a integer)
RETURNS real
LANGUAGE PLPGSQL
AS $$
DECLARE
sg real;
num real;
den real;
BEGIN
-- EXECUTE format('select count(*) from %I where coach like %L', 'empty_seats_'||train_id||to_char(date,'_yyyy_mm_dd'), coach_type ||'%') into available;
EXECUTE format('select sum(grade * credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_a, year_a) into num;
EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_a, year_a) into den;
sg := num / den;
return sg;
-- select sum(grade * credit) into num from current_user+'_t'
END;
$$;

-- sum(credtis) for each courses in that sem,year
CREATE OR REPLACE FUNCTION semcredits(sem_a integer, year_a integer)
RETURNS real
LANGUAGE PLPGSQL
AS $$
DECLARE
den int;
BEGIN
-- EXECUTE format('select count(*) from %I where coach like %L', 'empty_seats_'||train_id||to_char(date,'_yyyy_mm_dd'), coach_type ||'%') into available;

EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_a, year_a) into den;
return den;
-- select sum(grade * credit) into num from current_user+'_t'
END;
$$;

-- CREATE TABLE current_ay(
--     sem integer,
--     year integer
-- );

CREATE OR REPLACE FUNCTION yearsem()
RETURNS RECORD
LANGUAGE PLPGSQL
AS $$
DECLARE
ret record;
BEGIN
select extract(year from now()) as year, extract(month from now()) as sem into ret;

if ret.sem <=6 then
ret.sem=2;
ret.year=ret.year-1;
else
ret.sem=1;
end if;

return ret;
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
-- select (sem,year) into (sem_c,year_c) from current_ay;
-- sem_c and year_c from current time
select yearsem() into (year_c, sem_c);

-- going to the prev semester courses
if sem_c=2 then 
sem_c=1;

else 
    sem_c=2;
    year_c=year_c-1;
end if;
-- select sum(credits) into last_credit from postgres_t where sem=sem_c and year=year_c;
EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_c, year_c) into last_credit;

if sem_c=2 then 
sem_c=1;
year_c=year_c-1;
else 
sem_c=2;
end if;
EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_c, year_c) into last_credit2;
avg_credit=(last_credit+last2_credit)/2.0;
return avg_credit;
END;
$$;


-- postgres_t 
CREATE TABLE postgres_t (
    courseid varchar(7) primary key,
    credits real not null,
    sem integer not null,
    year integer not null,
    grade integer not null
);
insert into postgres_t values('MA101',3,1,2019,2);
insert into postgres_t values('CS101',3,2,2019,9);
insert into postgres_t values('CS201',4,1,2020,10);
insert into postgres_t values('CS204',4,2,2020,8);
insert into postgres_t values('BM101',3,2,2020,8);
insert into postgres_t values('GE107',1.5,2,2020,9);
insert into postgres_t values('CS301',4,1,2021,8);
insert into postgres_t values('CS302',3,1,2021,9);
insert into postgres_t values('CS303',4,1,2021,7);


-- insert into course_catalog values('CS301', 3, 1, 2, 6, 4);
-- insert into pre_requisite values('CS201', 'GE103');
-- EXECUTE format('CREATE TABLE %I (
--     courseid varchar(7) primary key,
--     credits real not null,
--     sem integer not null,
--     year integer not null,
--     grade integer not null
--     );', studentid || '_t');

/*
time table
1 to 5 for mon to friday
time slot
1 for 9 to 10
2 for 10 to 11
3 for 11 to 12
4 for 12 to 1
5 for 1 to 2
...

*/

CREATE OR REPLACE FUNCTION check_enrollment()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
DECLARE
PR record;
avg_last_two_sem_credit real;
this_sem_credit real;
this_course_credit real;
BEGIN
--execute format('INSERT INTO %I VALUES(%L)',  current_user || '_e', courseid);
-- NEW.courseid, course offering table
-- check course existence - ok
-- pre_req - 
-- batch
-- time-table
-- 1.25 rule
if NEW.courseid not in (select course_offerings.courseid from course_offerings) then
raise exception 'Invalid Course !!';
end if;

for PR in (select * from pre_requisite where pre_requisite.courseid =  NEW.courseid) loop
if PR.pre_req not in EXECUTE format('select courseid from %I where grade >= 4;', current_user || '_t') then
raise exception 'Prequisite not satisfied !!';
end if;
end loop;

-- 2019csb1119 -> 2019csb
if substr(current_user, 1, 7) not in (select course_batches.batch from course_batches where course_batches.courseid = NEW.courseid) then
raise exception 'Unavailable for your batch !!';
end if;

-- timetable

--1.25 rule
select lasttwosemcredit() into avg_last_two_sem_credit;
EXECUTE format('select sum(credits) from %I where sem=%L and year=%L;', current_user||'_t', sem_c, year_c) into this_sem_credit;
select credits into this_course_credit from course_catalog where courseid = NEW.courseid;
this_sem_credit := this_sem_credit + this_course_credit;
avg_last_two_sem_credit := 1.25 * avg_last_two_sem_credit;
if this_sem_credit > avg_last_two_sem_credi then
raise exception 'Credit Limit Exceeded!!';
end if;
RETURN NEW;
END;
$$;

CREATE TRIGGER check_enrollment
BEFORE INSERT
ON postgres_e
FOR EACH ROW
EXECUTE PROCEDURE check_enrollment();


--
-- 2019 csb 1119 (lower case only)
CREATE OR REPLACE FUNCTION create_student(studentid varchar(12))
RETURNS void
LANGUAGE PLPGSQL
AS $$
BEGIN
EXECUTE format('CREATE USER %I WITH PASSWORD ''123''', studentid);
-- Transcript table
EXECUTE format('CREATE TABLE %I (
    courseid varchar(7) primary key,
    credits real not null,
    sem integer not null,
    year integer not null,
    grade integer not null
    );', studentid || '_t');
-- Enrolled table
EXECUTE format('CREATE TABLE %I (
    courseid varchar(7),
    sem integer not null,
    year integer not null,
    primary key(courseid, sem, year)
    );', studentid || '_e');
-- History/Request table
EXECUTE format('CREATE TABLE %I (
    courseid varchar(7) primary key,
    sem integer not null,
    secid integer,
    year integer not null,
    status varchar(50) not null
    );', studentid || '_h');
END;
$$;
/*
-- create table nn1(val int);

CREATE OR REPLACE FUNCTION sce2()
RETURNS TRIGGER
LANGUAGE PLPGSQL SECURITY DEFINER
AS $$
BEGIN
insert into nn1 values(NEW.val);
return NEW;
END;
$$;

CREATE OR REPLACE FUNCTION sce()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
raise notice 'nice %', current_user;
if NEW.val = 0 then
raise exception 'not ok';
end if;
return NEW;
END;
$$;

CREATE TRIGGER nn2_trig
BEFORE INSERT
ON nn2
FOR EACH ROW
EXECUTE PROCEDURE sce();

CREATE TRIGGER nn2_trig_2
AFTER INSERT
ON nn2
FOR EACH ROW
EXECUTE PROCEDURE sce2();

CREATE OR REPLACE FUNCTION blackbox(i integer)
RETURNS void
LANGUAGE PLPGSQL
AS $$
BEGIN
insert into nn2 values(i);
raise notice 'success';
END;
$$;

grant select, insert on nn2 to nice1;
grant all on function blackbox to nice1;

REVOKE ALL ON FUNCTION sce FROM PUBLIC;

student_e insert, check in trigger
insert ho gaya
after insert wala trigger (security definer)
insert course_e
*/