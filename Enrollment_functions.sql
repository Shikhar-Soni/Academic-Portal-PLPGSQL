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