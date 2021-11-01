---------------------------------------------
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

execute format('grant select on %I to %I;', NEW.studentid || '_t', NEW.studentid);
execute format('grant select, insert on %I, %I to %I;', NEW.studentid || '_h', NEW.studentid || '_e', NEW.studentid);
return NEW;
END;
$$;

CREATE TRIGGER student_info_t
BEFORE INSERT
ON student_info
FOR EACH ROW
EXECUTE PROCEDURE create_student();

insert into student_info values('2019csb1072', 'Name Surname', 'CSE');
insert into student_info values('2019csb1063', 'Nice Guy', 'CSE');
insert into student_info values('2019meb1214', 'Another Guy', 'ME');

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

execute format('create user %I with password ''123'';', NEW.teacherid);

execute format('CREATE TABLE IF NOT EXISTS %I (courseid varchar(7),
sem integer not null,
year integer not null,
status varchar(50) not null,
secid integer not null,
entry_no varchar(12),
primary key(courseid, entry_no));', NEW.teacherid || '_h');

execute format('GRANT SELECT, UPDATE on %I to %I;', NEW.teacherid || '_h', NEW.teacherid);

return NEW;
END;
$$;

CREATE TRIGGER instructor_info_t
BEFORE INSERT
ON instructor_info
FOR EACH ROW
EXECUTE PROCEDURE create_instructors();

insert into instructor_info values(92, 'Teacher Person', 'CSE', 'cs303', 1);
-- insert into instructor_info values(91, 'Teacher Person', 'CSE', 'ge103', 1);
insert into instructor_info values(91, 'Person Person', 'CSE', 'cs301', 1);
-- insert into instructor_info values(92, 'Person Person', 'CSE', 'cs203', 1);
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

select * from course_catalog;

create table pre_requisite(
courseid varchar(7) not null,
pre_req varchar(7) not null
);

insert into pre_requisite values('cs201', 'ge103');
insert into pre_requisite values('cs202', 'cs201');
insert into pre_requisite values('cs302', 'cs101');
insert into pre_requisite values('cs302', 'cs201');
insert into pre_requisite values('cs204', 'cs203');
insert into pre_requisite values('cs301', 'cs201');
insert into pre_requisite values('cs302', 'cs204');
insert into pre_requisite values('cs302', 'cs201');

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
BEGIN
-- we will create course grade as well as course enrollment table (any one can view the enrollment table as in aims)
EXECUTE format('CREATE TABLE %I (studentid varchar(12));', NEW.courseid || NEW.secid || '_e');
EXECUTE format('CREATE TABLE %I (studentid varchar(12) primary key, grade integer);', NEW.courseid || NEW.secid || '_g');

execute format('GRANT select, insert, update on %I to %I;', NEW.courseid || NEW.secid || '_g', NEW.teacherid);
execute format('GRANT select on %I to PUBLIC;', NEW.courseid || NEW.secid || '_e');

RETURN NEW;
END;
$$;

CREATE TRIGGER insert_course_offering
BEFORE INSERT
ON course_offerings
FOR EACH ROW
EXECUTE PROCEDURE create_course_sec_table();

-- course, teacherid, sec, sem, yr, cg
insert into course_offerings values('cs301', 91, 1, 1, 2021, 7.0);
insert into course_offerings values('cs302', 93, 1, 1, 2021, 7.0);
insert into course_offerings values('cs303', 92, 1, 1, 2021, 8.0);

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

insert into "2019csb1063_t" values ('ma101', 3, 1, 2019, 7);
insert into "2019csb1063_t" values ('ge103',  4.5, 1, 2019, 8);
insert into "2019csb1063_t" values ('ns101', 1, 1, 2019, 10);
insert into "2019csb1063_t" values ('cs101', 3, 2, 2019, 7);
insert into "2019csb1063_t" values ('ma102', 3, 2, 2019, 8);
insert into "2019csb1063_t" values ('ma102', 3, 2, 2019, 9);
insert into "2019csb1063_t" values ('ns102', 1, 2, 2019, 9);
insert into "2019csb1063_t" values ('cs201', 4, 1, 2020, 9);
insert into "2019csb1063_t" values ('cs203', 4, 1, 2020, 9);
insert into "2019csb1063_t" values ('cs202', 4, 2, 2020, 7);
insert into "2019csb1063_t" values ('cs204', 4, 2, 2020, 9);

insert into "2019meb1214_t" values('cs101', 3, 2, 2019, 9);
insert into "2019meb1214_t" values('ge103', 4.5, 1, 2019, 9);
insert into "2019meb1214_t" values('cs201', 4, 1, 2020, 9);
insert into "2019meb1214_t" values('cs203', 4, 1, 2020, 9);
insert into "2019meb1214_t" values('cs202', 4, 2, 2020, 8);
insert into "2019meb1214_t" values('cs204', 4, 2, 2020, 10);

----------------------------------------------------------------------------------------------------------

