use mes_test_db;

select * from production_lines; -- dây chuyền sản xuất
select * from products; -- sản phẩm cần sản xuất
select * from machines; -- máy móc
select * from employees; -- nhân viên
select * from work_orders; -- lệnh sản xuất
select * from production_logs; -- nhật ký sản xuất
select * from materials; -- Danh mục nguyên vật liệu để làm ra sản phẩm
select * from work_order_materials; -- Số lượng vật tư dự kiến của từng lệnh
select * from material_stocks; -- Số lượng tồn kho hiện tại
select * from stock_movements; -- Nhật ký nhập, xuất, điều chỉnh tồn kho
select * from machine_status_history; -- Lịch sử thay đổi trạng thái máy

-- Thứ tự thực hiện các lệnh sql:
-- 1 FROM / JOIN: Xác định bảng nguồn và kết hợp dữ liệu
-- 2 WHERE: Lọc từng dòng
-- 3 GROUP BY: Gom các dòng thành nhóm
-- 4 HAVING: Lọc các nhóm
-- 5 SELECT: Tạo các biểu thức và alias đầu ra
-- 6 DISTINCT: Loại bỏ dòng trùng
-- 7 ORDER BY: Sắp xếp kết quả
-- 8 LIMIT / OFFSET: Giới hạn số dòng trả về

select 
	wo.order_code,
    m.code as material_code,
    m.name as material_name,
    wom.required_quantity,
    m.unit as material_unit
from work_order_materials wom
join work_orders wo on wo.id = wom.work_order_id
join materials m on m.id = wom.material_id;

-- Window Functions cho phép thực hiện các phép tính trên một tập dòng liên quan mà không nhất thiết gom nhiều dòng thành một dòng như GROUP BY.
-- GROUP BY làm giảm số dòng, trong khi Window Function vẫn giữ các dòng chi tiết và bổ sung kết quả tính toán.
-- FUNCTION() OVER (
--     PARTITION BY column
--     ORDER BY column
--     ROWS BETWEEN ...)
-- over(): xđ đây là window function
-- partition by: chia dữ liệu thành các nhóm tính toán
-- order by: xđ thứ tự các rows trong các nhóm tính toán
-- rows between: xđ khung các dòng dùng để tính toán

SELECT -- đây khi dùng group by sẽ làm giảm số dòng
    machine_id,
    SUM(good_quantity) AS total_good
FROM production_logs
GROUP BY machine_id;

SELECT -- đây là dùng window function vẫn giữ được các dòng chi tiết và bổ sung thêm cột tính toán
    id,
    machine_id,
    good_quantity,
    SUM(good_quantity) OVER (
        PARTITION BY machine_id
    ) AS total_good
FROM production_logs
WHERE machine_id = 1;

-- tìm bản ghi sản xuất log mới nhất của mỗi máy
with ranked_logs as (
	SELECT
		machine_id,
		id AS log_id,
		produced_at,
		ROW_NUMBER() OVER ( -- hàm row_number giúp đánh số thứ tự liên tiếp cho từng dòng dữ liệu trong 1 tập kết quả
			PARTITION BY machine_id -- gom nhóm theo id máy
			ORDER BY produced_at DESC, id DESC -- sắp xếp theo tg mới nhất, nếu 2 bản ghi cùng produced_at thì id sẽ quyết định thứ tự
		) AS rn
	FROM production_logs -- ko thể dùng trực tiếp where nếu muốn lấy bản mới nhất mỗi máy bởi window func được chạy sau where nên ta phải dùng CTE
)
select * from ranked_logs where rn = 1; -- lấy ra bản ghi mới nhất của mỗi máy

-- ROW_NUMBER: Mỗi dòng nhận một số thứ tự riêng.
-- RANK: Các dòng đồng hạng nhận cùng thứ hạng, tạo khoảng trống thứ hạng tiếp theo.
-- DENSE_RANK: Các dòng đồng hạng nhận cùng thứ hạng, không tạo khoảng trống.

-- xếp hạng các máy dựa trên tổng sản lượng đã sx được
WITH machine_summary AS (
    SELECT
        m.id,
        m.code,
        COALESCE(SUM(log.good_quantity), 0)
            AS total_good
    FROM machines m
    LEFT JOIN production_logs log
        ON m.id = log.machine_id
    GROUP BY m.id, m.code
)
SELECT
    code,
    total_good,
    RANK() OVER (
        ORDER BY total_good DESC
    ) AS production_rank,
    DENSE_RANK() OVER (
        ORDER BY total_good DESC
    ) AS densee_rank
FROM machine_summary;

-- tính tổng luỹ kế qua mỗi ngày của từng máy
-- ví dụ ngày thứ 1 máy 1 đc 100 thì tổng tích luỹ là 100, ngày thứ 2 là 500 thì tổng tích luỹ bằng 100 + 500 = 600
with daily_production as (
	-- đầu tiên select tổng sản phầm trong 1 ngày của từng máy
	select machine_id, date(produced_at) as production_date, sum(good_quantity) as daily_good
	from production_logs
	group by machine_id, date(produced_at) -- gom nhóm cùng 1 máy và cùng 1 ngày để tính
)
select
	machine_id,
    daily_good,
    production_date,
    sum(daily_good) over(
		partition by machine_id -- gom nhóm theo id máy
        order by production_date -- sx theo ngày sản suất
        rows between -- xđ khung tính toán theo vị trí dòng
			unbounded preceding -- từ dòng đầu tiên trong nhóm tính toán 
            and current row -- đến dòng hiện tại trong nhóm tính toán 
		-- ví dụ trong nhóm máy 1, đang duyệt đến dòng 1 thì tổng luỹ kế tính từ dòng 1 đến dòng hiện tại là dòng 1
        -- duyệt đến dòng 2 thì tổng luỹ kế cộng tử dòng 1 đến dòng hiện tại là 2
    ) as cumulative_good
from daily_production
order by machine_id, production_date;

-- LAG và LEAD: Hai hàm này dùng để lấy giá trị của dòng trước hoặc dòng sau trong một phân vùng có thứ tự.
-- LAG(column): Lấy giá trị từ dòng trước.
-- LEAD(column): Lấy giá trị từ dòng sau.

-- Xem thời gian giữa hai lần ghi nhận sản lượng liên tiếp của cùng một máy.
WITH log_times AS (
    SELECT
        machine_id,
        produced_at,
        LAG(produced_at) OVER ( -- tạo 1 cột lấy thời gian của row trước trong nhóm tính toán, nếu là bản ghi đầu tiên thì cột này null
            PARTITION BY machine_id
            ORDER BY produced_at, id
        ) AS previous_time
    FROM production_logs
)
SELECT
    machine_id,
    produced_at,
    previous_time,
    TIMESTAMPDIFF(
        MINUTE,
        previous_time,
        produced_at
    ) AS minutes_since_previous_log
FROM log_times
ORDER BY machine_id, produced_at;


--------------------------------------------------------------------------------------------------------------------------------------

-- 3 lệnh sản xuất có số lượng kế hoạch lớn nhất chưa bị huỷ
select order_code, product_id, planned_quantity, status
from work_orders where status != 'CANCELLED'
order by planned_quantity desc limit 3;

-- Lệnh có số lượng kế hoạch từ 500 đến 1000
select * from work_orders
where planned_quantity between 500 and 1000;

-- Lệnh thuộc một trong hai trạng thái Bất kỳ
select * from work_orders
where status in ('COMPLETED', 'CANCELLED');

-- Tìm mã lệnh bắt đầu bằng WO-00
select * from work_orders
where order_code like 'WO-00%';

-- Nhân viên chưa được phân công dây chuyền
select * from employees
where line_id is null;

-- Phân loại lệnh sản xuất theo số lượng kế hoạch
select order_code, planned_quantity,
	case
		when planned_quantity >= 1000 then 'LARGE'
        when planned_quantity >= 500 then 'MEDIUM'
        else 'SMALL'
	end as order_size
from work_orders;

start transaction;
update machines set status = 'IDLE' where id = 1;
rollback;

-- hiển thị mã lệnh, tên sản phẩm, tên dây chuyền sản xuất và số lượng sp theo kế hoạch
select wo.order_code, p.name as product_name, pl.name as line_name, wo.planned_quantity
from work_orders wo
join products p on wo.product_id = p.id
join production_lines pl on wo.line_id = pl.id;

-- inner join lấy phân giao nhau
-- left join lấy phần giao nhau và phần bên trái

-- Liệt kê tất cả máy và tổng số sản phẩm đạt chuẩn của từng máy, kể cả máy chưa từng sản xuất.
select m.code, m.name, coalesce(sum(plg.good_quantity), 0) as total_good_quantity from machines m
left join production_logs plg on m.id = plg.machine_id -- dùng left join để lấy cả máy chưa từng sx
group by m.id, m.code, m.name;

-- Tổng hợp số lượng sản xuất theo lệnh.
select
	wo.order_code,
    wo.planned_quantity,
    coalesce(sum(plg.good_quantity), 0) as total_good,
    coalesce(sum(plg.defect_quantity), 0) as total_defect
from work_orders wo
left join production_logs plg on wo.id = plg.work_order_id -- left join để lấy cả lệnh chưa được dùng để sx
group by wo.order_code, wo.planned_quantity;

-- Tìm các lệnh có tổng sản phẩm đạt chuẩn dưới 80% kế hoạch.
select
	wo.order_code,
    wo.planned_quantity,
    wo.status,
    coalesce(sum(plg.good_quantity), 0) as total_good
from work_orders wo
left join production_logs plg on wo.id = plg.work_order_id
where wo.status != 'CANCELLED' -- lọc trước khi gom nhóm
group by wo.id, wo.order_code, wo.planned_quantity -- gom nhóm
having total_good < wo.planned_quantity * 0.8; -- lọc sau khi gom nhóm

-- Tìm các lệnh có số lượng kế hoạch lớn hơn mức trung bình của tất cả lệnh.
select * from work_orders
where planned_quantity > (select avg(planned_quantity) from work_orders);

-- Tìm sản phẩm có ít nhất một lệnh sản xuất đã hoàn thành.
select p.id, p.name from products p
where exists (select 1 from work_orders wo where wo.product_id = p.id and wo.status = 'COMPLETED');

-- union => loại bỏ các dòng trùng
-- union all => giữ nguyên các dòng trùng, cost less
-- đều cần cùng số cột và kiểu dữ liệu
select order_code, status from work_orders
where status = 'PLANNED'

union all

select order_code, status from work_orders
where status = 'COMPLETED';


-- Bài 1: Lấy danh sách các lệnh sản xuất có planned_quantity > 700, sắp xếp giảm dần.
select * from work_orders
where planned_quantity > 700
order by planned_quantity desc;

-- Bài 2: Tìm nhân viên chưa được phân công vào dây chuyền sản xuất.
select * from employees
where line_id is null;

-- Bài 3: Dùng CASE WHEN phân loại máy thành ACTIVE nếu RUNNING, INACTIVE neu trạng thái khác.
select code, name, status,
	case
		when status = 'RUNNING' then 'ACTIVE'
        else 'INACTIVE'
	end as status_machine
from machines;

-- Bài 4: Hiển thị mã lệnh, tên sản phẩm, tên dây chuyền và số lượng kế hoạch.
select wo.order_code, p.name as product_name, pl.name as line_name, wo.planned_quantity
from work_orders wo
join products p on wo.product_id = p.id
join production_lines pl on wo.line_id = pl.id
order by wo.planned_quantity desc;

-- Bài 5: Tính tổng sản phẩm đạt chuẩn và lỗi của từng dây chuyền, kể cả dây chuyền chưa có sản lượng.
select pl.id, pl.name, coalesce(sum(plg.good_quantity), 0) as total_good, coalesce(sum(plg.defect_quantity), 0) as total_defect
from production_lines pl
left join machines m on pl.id = m.line_id
left join production_logs plg on m.id = plg.machine_id
group by pl.id, pl.name;

-- Bài 6: Tìm các máy chưa từng xuất hiện trong production_logs.
select m.id, m.code from machines m
left join production_logs plg on m.id = plg.machine_id
where plg.machine_id is null;

-- Bài 7: Tìm các sản phẩm có tổng số lượng kế hoạch lớn hơn 1000.
select p.id, p.name, sum(wo.planned_quantity) as total_planned from products p
join work_orders wo on p.id = wo.product_id
group by p.id
having total_planned > 1000;

-- Bài 8: Tìm lệnh sản xuất có tỷ lệ lỗi lớn hơn 3%. Tỷ lệ lỗi = lỗi / (đạt + lỗi) * 100.
select
	wo.id, 
	wo.order_code,
    sum(plg.good_quantity) as total_good,
    sum(plg.defect_quantity) as total_defect,
	round(
		sum(plg.defect_quantity) * 100 /
		nullif( -- nullif(exp1, exp2) => nếu exp1 = exp2 trả về null, nếu exp1 != exp2 trả về exp1
			sum(plg.good_quantity) + sum(plg.defect_quantity),
            0
		),
        2
	) as defect_rate
from work_orders wo
join production_logs plg on wo.id = plg.work_order_id
group by wo.id, wo.order_code
having defect_rate > 3;

-- Bài 9: Dùng EXISTS tìm các sản phẩm chưa từng có lệnh sản xuất COMPLETED.
select * from products p
where not exists (
	-- xét từng sp, tồn tại sp nào trong các lệnh có trạng thái completed thì loại
	select 1 from work_orders wo where wo.product_id = p.id and wo.status = 'COMPLETED'
);

-- Bài tập nhỏ 9.1: Hãy tự sửa câu SQL ở bài 9 trên để tìm các máy chưa từng có production_logs,
-- nhưng bắt buộc phải dùng NOT EXISTS, không dùng LEFT JOIN
select * from machines m
where not exists (
	-- xét từng máy, máy nào có id trong bảng log thì loại
	select 1 from production_logs plg where plg.machine_id = m.id
);

-- Bài 10: Dùng CTE tính tổng sản phẩm đạt chuẩn của từng lệnh, sau đó tìm các lệnh có 
-- sản lượng đạt chuẩn thấp hơn mức trung bình của các lệnh đã có log.
with order_summary as (
	select wo.id, wo.order_code, coalesce(sum(plg.good_quantity), 0) as total_good from work_orders wo
	join production_logs plg on wo.id = plg.work_order_id
	group by wo.id, wo.order_code, wo.planned_quantity
)
select order_code, total_good from order_summary
where total_good < (select avg(total_good) from order_summary)
order by total_good desc;

-- Bài 11: Tạo báo cáo từng lệnh sản xuất gồm order_code, product_name, planned_quantity, total_good, total_defect và completion_rate (%)
-- Phải hiển thị cả lệnh chưa có log, không được tính sai planned_quantity.
select
	wo.order_code,
    p.name as product_name,
    wo.planned_quantity,
    coalesce(sum(plg.good_quantity), 0) as total_good,
    coalesce(sum(plg.defect_quantity), 0) as total_defect,
    round(
		coalesce(sum(plg.good_quantity), 0) * 100 / nullif(wo.planned_quantity, 0),
        2
    ) as completion_rate
from work_orders wo
join products p on p.id = wo.product_id
left join production_logs plg on plg.work_order_id = wo.id
group by wo.id, wo.order_code, wo.planned_quantity
order by completion_rate desc;

-- Bài 12: Tìm các máy có tỷ lệ sản phẩm lỗi lớn hơn 3%, chỉ xét máy đã ghi nhận ít nhất một sản phẩm.
-- Hiển thị machine_code, total_good, total_defect, defect_rate.
select m.code, sum(plg.good_quantity) as total_good, sum(plg.defect_quantity) as total_defect,
	sum(
		plg.defect_quantity) * 100 /
		nullif(
			sum(plg.good_quantity) + sum(plg.defect_quantity),
            0
	) as defect_rate
from machines m
join production_logs plg on plg.machine_id = m.id
group by m.id, m.code
having defect_rate > 3
order by defect_rate desc;

-- Bài 13: Tìm những sản phẩm chưa có lệnh sản xuất COMPLETED, đồng thời hiển thị tổng số lượng kế hoạch của những lệnh chưa bị hủy.
-- Phải hiển thị cả sản phẩm chưa có lệnh nào, nếu có.
with planned_summary as (
	select product_id, sum(planned_quantity) as total_planned
    from work_orders
    where status != 'CANCELLED'
    group by product_id
)
select p.name as product_name, coalesce(ps.total_planned, 0) as total_planned from products p
left join planned_summary ps on ps.product_id = p.id
where not exists (select 1 from work_orders wo where wo.product_id = p.id and wo.status = 'COMPLETED')
order by total_planned desc;
