process_png_to_json() {
	local input="$1"
	local mode="$2"
	local custom="$3"
	local output

	# ... (省略中間的檔案名稱生成代碼) ...
	if [ -n "$custom" ]; then
		output="$custom"
	else
		local base="${input%.*}"
		if [ "$mode" = "o" ]; then
			output="${base}.json"
		elif [ "$mode" = "cn" ]; then
			output=$(generate_output_filename "${base}.json" true)
		elif [ "$mode" = "tw" ]; then output=$(generate_output_filename "${base}.json" false); fi
	fi

	if [ "$DRY_RUN" = true ]; then
		echo -e "${BLUE}[DRY]${NC} Extract: $input -> $output"
		return 0
	fi

	# ---------------------------------------------------------
	# 新增檢查
	# ---------------------------------------------------------
	local t_check=$(mktemp)
	if ! python3 -c "$PNG_HANDLER" extract_raw "$input" "$t_check" 2>/dev/null; then
		rm -f "$t_check"
		echo -e "${YELLOW}Skipping (no metadata): $input${NC}"
		return 0
	fi

	if ! file_contains_chinese "$t_check"; then
		rm -f "$t_check"
		echo -e "${YELLOW}Skipping (no Chinese content): $input${NC}"
		return 0
	fi
	rm -f "$t_check"
	# ---------------------------------------------------------

	if [ -f "$output" ] && [ "$MAKE_BACKUP" = true ]; then cp "$output" "${output}.bak"; fi

	if ! python3 -c "$PNG_HANDLER" extract_raw "$input" "$output" 2>&1; then
		echo -e "${RED}Error extracting $input${NC}" >&2
		return 1
	fi

	if [ "$mode" = "tw" ]; then
		local tmp=$(mktemp)
		opencc -i "$output" -o "$tmp" -c s2tw
		mv "$tmp" "$output"
		load_all_rules false
		apply_replacements "$output"
	elif [ "$mode" = "cn" ]; then
		load_all_rules true
		apply_replacements "$output"
		local tmp=$(mktemp)
		opencc -i "$output" -o "$tmp" -c tw2s
		mv "$tmp" "$output"
	fi
	echo -e "${GREEN}Wrote: $output${NC}"
}
