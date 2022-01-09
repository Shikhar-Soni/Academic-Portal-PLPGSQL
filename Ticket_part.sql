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
