/*

-- for j in (select distinct teacherid, courseid, secid from instructor_info)
-- loop

-- execute format('GRANT select, insert, update, delete on %I to %I;', courseid || secid || '_g', teacherid);

-- end loop;

CREATE OR REPLACE FUNCTION neci()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
DECLARE
str varchar(100);
BEGIN
str := '' || NEW.courseid || NEW.pre_req || ' __ ' || OLD.courseid || OLD.pre_req;
raise notice 'Value: %', str;
return NEW;
END;
$$;

CREATE TRIGGER niceh
AFTER UPDATE
ON pre_requisite
FOR EACH ROW
EXECUTE PROCEDURE neci();

UPDATE pre_requisite SET pre_req = 'changed' where courseid = 'cs201';
*/

CREATE OR REPLACE FUNCTION ticket(course varchar(12), sm integer, sec integer, yr integer)
RETURNS void
LANGUAGE PLPGSQL
AS $$
BEGIN

END;
$$;


create table "2928_h"(
    nice integer
);
insert into "2928_h" values(10);
select * from "2928_h";


------------------------------------

create table student_info(
    studentid varchar(12) primary key,
    _name varchar(50) not null,
    dept_name varchar(20) not null
);

-- insert into student_info values('2019csb1119', 'Shikhar Soni', 'CSE');
-- insert into student_info values('2019csb1084', 'Het Fadia', 'CSE');
-- insert into student_info values('2019csb1064', 'Aditya Agarwal', 'CSE');
insert into student_info values('2019csb1072', 'Name Surname', 'CSE');
insert into student_info values('2019csb1063', 'Nice Guy', 'CSE');
insert into student_info values('2019meb1214', 'Another Guy', 'ME');
-- insert into student_info values('2019meb1252', 'Some One', 'ME');
-- insert into student_info values('2019mcb1141', 'Another One', 'MNC');
-- insert into student_info values('2019mmb1372', 'Random guy', 'MM');
-- insert into student_info values('2019meb1217', 'Guy Random', 'ME');

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
    secid integer not null,
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

CREATE OR REPLACE FUNCTION generate_students()
RETURNS void
LANGUAGE PLPGSQL
AS $$
DECLARE
i record;
BEGIN
-- this function generates 10 students for testing every functionality appropriately

for i in (select * from student_info)
loop
perform create_student(i.studentid);
execute format('GRANT select on %I to %I', i.studentid || '_t', i.studentid);
-- grant them select to enrollment table of course on enrollment too
execute format('GRANT select, insert on %I, %I to %I', i.studentid || '_e', i.student || '_h', i.studentid);

end loop;

END;
$$;

create table instructor_info(
    teacherid integer,
    _name varchar(50) not null,
    dept_name varchar(20) not null,
    courseid varchar(7),
    secid integer,
    primary key(courseid, secid)
);

insert into instructor_info values(1, 'Teacher Person', 'CSE', 'cs303', 1);
insert into instructor_info values(1, 'Teacher Person', 'CSE', 'ge103', 1);
insert into instructor_info values(2, 'Person Person', 'CSE', 'cs301', 1);
insert into instructor_info values(2, 'Person Person', 'CSE', 'cs203', 1);
insert into instructor_info values(2, 'Person Person', 'CSE', 'ma101', 2);
insert into instructor_info values(3, 'Person Teacher', 'MATH', 'cs302', 1);
insert into instructor_info values(3, 'Person Teacher', 'MATH', 'cs201', 1);
insert into instructor_info values(3, 'Person Teacher', 'MATH', 'ma101', 1);
insert into instructor_info values(4, 'Am Instructor', 'CSE', 'ge103', 2);

CREATE OR REPLACE FUNCTION generate_instructors()
RETURNS void
LANGUAGE PLPGSQL
AS $$
DECLARE
i record;
BEGIN
-- this function generates 4 instructors for testing every functionality appropriately
/*
    GRANT select, insert, update on cs3011_g, cs3021_g to user;
    GRANT ALL ON FUNCTION load_grade TO user;
    GRANT pg_read_server_files TO user;
*/

for i in (select distinct teacherid from instructor_info)
loop

execute format('create user %I with password ''123'';', i.teacherid);

execute format('CREATE TABLE IF NOT EXISTS %I (courseid varchar(7),
sem integer not null,
year integer not null,
status varchar(50) not null,
secid integer not null,
entry_no varchar(12),
primary key(courseid, entry_no));', i.teacherid || '_h');

execute format('GRANT SELECT, UPDATE, DELETE on %I to %I;', i.teacherid || '_h', i.teacherid);
execute format('GRANT ALL ON FUNCTION load_grade to %I;', i.teacherid);
execute format('GRANT pg_read_server_files TO %I;', i.teacherid);

end loop;

END;
$$;

create table ba_info(
    batchadvisorid varchar(8),
    teacherid integer,
    primary key(batchadvisorid)
);

insert into ba_info values('2019csb', 6);
insert into ba_info values('2019meb', 7);
insert into ba_info values('2019mmb', 8);
insert into ba_info values('2019mcb', 9);
CREATE USER "6" with password '123';
CREATE USER "7" with password '123';
CREATE USER "8" with password '123';
CREATE USER "9" with password '123';
create table "2019csb_h"(courseid varchar(7), sem integer not null, year integer not null, status varchar(50) not null, secid integer not null, entry_no varchar(12), primary key(courseid, entry_no));
create table "2019meb_h"(courseid varchar(7), sem integer not null, year integer not null, status varchar(50) not null, secid integer not null, entry_no varchar(12), primary key(courseid, entry_no));
create table "2019mmb_h"(courseid varchar(7), sem integer not null, year integer not null, status varchar(50) not null, secid integer not null, entry_no varchar(12), primary key(courseid, entry_no));
create table "2019mcb_h"(courseid varchar(7), sem integer not null, year integer not null, status varchar(50) not null, secid integer not null, entry_no varchar(12), primary key(courseid, entry_no));
GRANT select, update, delete on "2019csb_h" to "6";
GRANT select, update, delete on "2019meb_h" to "7";
GRANT select, update, delete on "2019mmb_h" to "8";
GRANT select, update, delete on "2019mcb_h" to "9";

create table dean_h(
courseid varchar(7),
sem integer not null,
year integer not null,
status varchar(50) not null,
secid integer not null,
entry_no varchar(12),
primary key(courseid, entry_no)
);

