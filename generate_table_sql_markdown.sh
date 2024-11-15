#!/usr/bin/env bash
# generate_table_sql_markdown.sh
#

mysql=
host=
port=3306
user=
password=''
database=
output_file=sql.md

$mysql -h $host -P$port -u $user -p"$password" --database $database -e "show tables;" |
    grep -v Tables_in_bill_beta |
    awk '{print "SHOW CREATE TABLE " $1 ";"}' |
    $mysql -h $host -P$port -u $user -p"$password" --database $database |
    grep -Ev '^Table.*Create Table' |
    awk '{
    # 提取第一个字段
    first_field = $1
    # 提取其余部分
    rest_of_line = substr($0, index($0, $2))
    # 输出格式化内容
    print "## " first_field "\n\n" "```sql\n" rest_of_line "\n```\n"
    }' |
    awk '{gsub(/\\n/, "\n"); print}' |
    awk 'NF {last_non_empty=NR} {lines[NR]=$0} END {for (i=1; i<=last_non_empty; i++) print lines[i]}' >$output_file

exit 0
