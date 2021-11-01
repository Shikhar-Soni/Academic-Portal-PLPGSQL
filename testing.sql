/*
CREATE OR REPLACE FUNCTION name()
RETURNS void
LANGUAGE PLPGSQL
AS $$
DECLARE
BEGIN

END;
$$;
*/

create table postgres_t(
    courseid varchar(7) primary key,
    credits real not null,
    sem integer not null,
    year integer not null,
    grade integer not null
);

insert into postgres_t values('cs101', 3, 2, 2019, 9);
insert into postgres_t values('ge103', 4.5, 1, 2019, 9);
insert into postgres_t values('cs201', 4, 1, 2020, 9);
insert into postgres_t values('cs203', 4, 1, 2020, 9);
insert into postgres_t values('cs202', 4, 2, 2020, 8);
insert into postgres_t values('cs204', 4, 2, 2020, 10);

-- insert into "2019csb1743_t" values('cs201', 4, 1, 2020, 9);

create table postgres_e(
    courseid varchar(7),
    sem integer not null,
    year integer not null,
    primary key(courseid, sem, year)
);

-- insert into postgres_e values('cs303', 1, 2021);
-- insert into postgres_e values('cs301', 1, 2021);
-- insert into postgres_e values('cs302', 1, 2021);

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

avg_credit=(last_credit+last2_credit)/2.0;
return avg_credit;

END;
$$;

------------------------------------------------------------


CREATE OR REPLACE FUNCTION enrollment_clashes(_courseid varchar(7))
RETURNS integer
LANGUAGE PLPGSQL
AS $$
DECLARE
ret integer:=0;
_slot integer;
BEGIN
-- execute format('select courseid from %I;',current_user||'_e');
-- select slot into ret from time_table where time_table.courseid=_courseid;
-- (select "2019csb1084_e".courseid from "2019csb1084_e")
-- execute format ('select %I.courseid from %I',current_user||'_e', current_user||'_e');
-- (select postgres_e.courseid from postgres_e)
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
-- grade < 4.0 is fail and not counted in CG
for RT in execute format('select * from %I where grade > 4.0', current_user || '_t') loop
sum_c := sum_c + RT.credits;
ret := ret + RT.credits * RT.grade;
end loop;

ret := ret / sum_c;
return ret;
END;
$$;

-------------------------------------------------------------

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
--execute format('INSERT INTO %I VALUES(%L)',  current_user || '_e', courseid);
-- NEW.courseid, course offering table
-- check course existence - ok
-- pre_req - ok
-- batch - ok
-- time-table - ok
-- cg requirement - ok
-- 1.25 rule - ok

if NEW.courseid not in (select course_offerings.courseid from course_offerings) then
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

raise notice '% required CG', required_CG;

-- 1.25 rule
EXECUTE format('select sum(C) from (select courseid from %I where sem=%L and year=%L) as O, course_catalog as AB where AB.courseid=O.courseid', current_user||'_e', NEW.sem, NEW.year) into this_sem_credit;

execute format('select C from course_catalog where courseid = %L', NEW.courseid) into this_course_credit;
this_sem_credit := this_sem_credit + this_course_credit;
select lasttwosemcredit() into avg_last_two_sem_credit;
avg_last_two_sem_credit := avg_last_two_sem_credit * 1.25;
if avg_last_two_sem_credit < this_sem_credit then
raise exception '1.25 rule violated !! % % %', this_sem_credit, this_course_credit, avg_last_two_sem_credit;
end if;

raise exception 'success % % %', this_sem_credit, this_course_credit, avg_last_two_sem_credit;

RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION enroll(courseid varchar(7))
RETURNS void
LANGUAGE PLPGSQL
AS $$
DECLARE
sem_c integer;
year_c integer;
BEGIN
select a, b from yearsem() as (a integer, b integer) into sem_c, year_c;
execute format('INSERT INTO %I VALUES(%L, %L, %L)',  current_user || '_e', courseid, sem_c, year_c);
END;
$$;

CREATE TRIGGER check_enrollment_at
BEFORE INSERT
ON "2019meb1214_e"
FOR EACH ROW
EXECUTE PROCEDURE check_enrollment();