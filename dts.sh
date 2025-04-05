#!/bin/bash
# 脚本功能：自动解析 binwalk 输出中所有 Flattened device tree 的偏移量和大小，然后提取出对应 dtb 块

# 解析命令行参数
while getopts "n:" opt; do
    case $opt in
        n)
            INPUT_FILE="$OPTARG"
            ;;
        *)
            echo "Usage: $0 [-n input_file]"
            exit 1
            ;;
    esac
done

# 如果未提供输入文件，提示用户并退出
if [ -z "$INPUT_FILE" ]; then
    echo -e "\e[31mError: No input file specified. Use -n to specify the input file.\e[0m"
    echo "Usage: $0 [-n input_file]"
    exit 1
fi

# 检查并清理 output 目录
if [ -d "output" ]; then
    echo -e "\e[33mOutput directory exists. Cleaning up...\e[0m"
    rm -rf output
    if [ $? -eq 0 ]; then
        echo -e "\e[32mOutput directory cleaned successfully.\e[0m"
    else
        echo -e "\e[31mFailed to clean output directory. Exiting.\e[0m"
        exit 1
    fi
fi



# 提取后的目录结构
BASENAME=$(basename "$INPUT_FILE")
BINWALK_OUTPUT_DIR="output"

# 创建输出目录
mkdir -p $BINWALK_OUTPUT_DIR/dts
mkdir -p output/dtb_extracted
mkdir -p output

# 使用 binwalk -e 解包固件
echo "Running binwalk -e to extract firmware contents from $INPUT_FILE..."
binwalk -e "$INPUT_FILE" -C "$BINWALK_OUTPUT_DIR"
if [ $? -ne 0 ]; then
    echo -e "\e[31mBinwalk extraction failed.\e[0m"
    exit 1
fi
echo -e "\e[32mBinwalk extraction complete. Proceeding with further steps in $BINWALK_OUTPUT_DIR...\e[0m"

# 切换到解包目录
mv "$BINWALK_OUTPUT_DIR/_${BASENAME}.extracted/dtb_combined.bin" output && rm -rf "$BINWALK_OUTPUT_DIR/_${BASENAME}.extracted"
cd "$BINWALK_OUTPUT_DIR" || exit 1

# 获取包含 "Flattened device tree" 的行（假设 binwalk 输出格式符合预期）
binwalk_output=$(binwalk "dtb_combined.bin" | grep "Flattened device tree")

# 初始化块计数器
count=0

# 遍历每一行，提取偏移量和大小信息
echo "$binwalk_output" | while read -r line; do
    # 第一列为偏移量（十进制）
    offset=$(echo "$line" | awk '{print $1}')
    # 使用 sed 提取 "size: XXX bytes" 中的 XXX 数字
    size=$(echo "$line" | sed -n 's/.*size: \([0-9]\+\) bytes.*/\1/p')
    if [ -n "$offset" ] && [ -n "$size" ]; then
        count=$((count+1))
        output_file="dtb_extracted/fdt_${count}.dtb"
        echo "Extracting block $count: offset=$offset, size=$size bytes..."
        dd if=dtb_combined.bin of="$output_file" bs=1 skip="$offset" count="$size" status=none
        echo -e "\e[32mSaved block $count to $output_file\e[0m"
    fi
done

echo "Extraction complete."

# 批量转换 dtb 到 dts
for dtb in dtb_extracted/*.dtb; do
    output_dts="dts/$(basename "${dtb%.dtb}.dts")"
    echo "Converting $dtb to $output_dts..."
    dtc -I dtb -O dts -o "$output_dts" "$dtb"
    if [ $? -eq 0 ]; then
        echo -e "\e[32mConverted successfully.\e[0m"
    else
        echo -e "\e[31mConversion failed for $dtb\e[0m"
    fi
done

echo -e "\e[32mAll extraction and conversion complete.\e[0m"
