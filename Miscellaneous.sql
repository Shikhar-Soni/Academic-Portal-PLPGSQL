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