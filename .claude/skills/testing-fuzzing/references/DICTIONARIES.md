# Fuzzing Dictionaries

## What Dictionaries Do

Fuzzing dictionaries are collections of tokens -- magic bytes, keywords, delimiters, and structural fragments -- that help coverage-guided fuzzers navigate past format-specific checks. Without a dictionary, a fuzzer generating random bytes will spend enormous time discovering that a JSON parser expects `{`, a PNG decoder expects `\x89PNG`, or an HTTP handler expects `GET `. Dictionaries seed the mutation engine with these tokens so the fuzzer can focus on exploring deeper program states.

**Usage with common fuzzers:**

```bash
# cargo-fuzz / libFuzzer
cargo fuzz run my_target -- -dict=dictionaries/json.dict

# AFL++
afl-fuzz -i corpus/ -o findings/ -x dictionaries/json.dict -- ./target

# libFuzzer standalone
./fuzz_target -dict=dictionaries/json.dict corpus/

# go-fuzz (place dictionary lines in workdir/dict/)
cp dictionaries/json.dict workdir/dict/
go-fuzz -bin=./fuzz.zip -workdir=workdir/
```

**Dictionary format:** Each line is `key="value"` where the value is a string literal. Use `\xNN` for hex bytes, `\\` for backslash, `\"` for quote. Lines starting with `#` are comments.

---

## JSON Dictionary

```
# json.dict -- JSON structural tokens and value patterns
json_obj_open="{"
json_obj_close="}"
json_arr_open="["
json_arr_close="]"
json_colon=":"
json_comma=","
json_quote="\""
json_null="null"
json_true="true"
json_false="false"
json_esc_newline="\\n"
json_esc_tab="\\t"
json_esc_backslash="\\\\"
json_esc_quote="\\\""
json_esc_slash="\\/"
json_esc_unicode="\\u0000"
json_esc_unicode_hi="\\uD800"
json_esc_unicode_lo="\\uDC00"
json_esc_backspace="\\b"
json_esc_formfeed="\\f"
json_esc_return="\\r"
json_zero="0"
json_neg="-1"
json_float="1.5"
json_exp="1e10"
json_negexp="1e-10"
json_posexp="1E+10"
json_maxint="9999999999999999"
json_minfloat="0.0000001"
json_empty_obj="{}"
json_empty_arr="[]"
json_empty_str="\"\""
json_nested="{{{"
json_kv="\"k\":\"v\""
json_ws=" "
json_bom="\xef\xbb\xbf"
```

---

## XML Dictionary

```
# xml.dict -- XML structural tokens, entities, and DTD fragments
xml_lt="<"
xml_gt=">"
xml_slash_gt="/>"
xml_lt_slash="</"
xml_amp="&"
xml_semicolon=";"
xml_eq="="
xml_quote="\""
xml_apos="'"
xml_comment_open="<!--"
xml_comment_close="-->"
xml_cdata_open="<![CDATA["
xml_cdata_close="]]>"
xml_pi_open="<?"
xml_pi_close="?>"
xml_pi_xml="<?xml version=\"1.0\"?>"
xml_pi_encoding="<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
xml_doctype="<!DOCTYPE"
xml_entity="<!ENTITY"
xml_element="<!ELEMENT"
xml_attlist="<!ATTLIST"
xml_notation="<!NOTATION"
xml_system="SYSTEM"
xml_public="PUBLIC"
xml_ndata="NDATA"
xml_xmlns="xmlns"
xml_xmlns_colon="xmlns:"
xml_ns_sep=":"
xml_entity_lt="&lt;"
xml_entity_gt="&gt;"
xml_entity_amp="&amp;"
xml_entity_quot="&quot;"
xml_entity_apos="&apos;"
xml_char_ref="&#x41;"
xml_char_ref_dec="&#65;"
xml_dtd_open="<!DOCTYPE root ["
xml_dtd_close="]>"
xml_external_entity="<!ENTITY xxe SYSTEM \"file:///etc/passwd\">"
xml_pcdata="#PCDATA"
xml_required="#REQUIRED"
xml_implied="#IMPLIED"
xml_cdata_attr="CDATA"
xml_id_attr="ID"
xml_idref="IDREF"
xml_nmtoken="NMTOKEN"
xml_any="ANY"
xml_empty="EMPTY"
xml_billion_laughs="<!ENTITY lol \"lol\">"
```

---

## HTML Dictionary

```
# html.dict -- Common HTML tags, attributes, and entities
html_doctype="<!DOCTYPE html>"
html_html="<html>"
html_head="<head>"
html_body="<body>"
html_div="<div>"
html_span="<span>"
html_p="<p>"
html_a="<a href=\"\">"
html_img="<img src=\"\">"
html_script="<script>"
html_script_close="</script>"
html_style="<style>"
html_style_close="</style>"
html_input="<input"
html_form="<form>"
html_table="<table>"
html_tr="<tr>"
html_td="<td>"
html_br="<br>"
html_hr="<hr>"
html_meta="<meta"
html_link="<link"
html_title="<title>"
html_iframe="<iframe"
html_textarea="<textarea>"
html_select="<select>"
html_option="<option>"
html_class="class=\"\""
html_id="id=\"\""
html_onclick="onclick=\"\""
html_onerror="onerror=\"\""
html_onload="onload=\"\""
html_onmouseover="onmouseover=\"\""
html_onfocus="onfocus=\"\""
html_src="src=\"\""
html_href="href=\"\""
html_action="action=\"\""
html_entity_nbsp="&nbsp;"
html_entity_lt="&lt;"
html_entity_gt="&gt;"
html_entity_amp="&amp;"
html_entity_quot="&quot;"
html_comment="<!-- -->"
html_svg="<svg"
html_math="<math>"
html_template="<template>"
html_slot="<slot>"
html_data_attr="data-x=\"\""
html_void_close=" />"
```

---

## SQL Dictionary

```
# sql.dict -- SQL keywords, operators, and injection patterns
sql_select="SELECT"
sql_insert="INSERT"
sql_update="UPDATE"
sql_delete="DELETE"
sql_from="FROM"
sql_where="WHERE"
sql_and="AND"
sql_or="OR"
sql_not="NOT"
sql_in="IN"
sql_like="LIKE"
sql_between="BETWEEN"
sql_join="JOIN"
sql_inner="INNER JOIN"
sql_left="LEFT JOIN"
sql_right="RIGHT JOIN"
sql_cross="CROSS JOIN"
sql_on="ON"
sql_group="GROUP BY"
sql_order="ORDER BY"
sql_having="HAVING"
sql_limit="LIMIT"
sql_offset="OFFSET"
sql_union="UNION"
sql_union_all="UNION ALL"
sql_create="CREATE TABLE"
sql_drop="DROP TABLE"
sql_alter="ALTER TABLE"
sql_index="CREATE INDEX"
sql_null="NULL"
sql_is_null="IS NULL"
sql_is_not_null="IS NOT NULL"
sql_asc="ASC"
sql_desc="DESC"
sql_distinct="DISTINCT"
sql_as="AS"
sql_case="CASE WHEN"
sql_then="THEN"
sql_else="ELSE"
sql_end="END"
sql_count="COUNT(*)"
sql_sum="SUM("
sql_avg="AVG("
sql_max="MAX("
sql_min="MIN("
sql_exists="EXISTS"
sql_semicolon=";"
sql_comment_line="--"
sql_comment_block="/*"
sql_comment_end="*/"
sql_squote="'"
sql_dquote="\""
sql_backtick="`"
sql_paren_open="("
sql_paren_close=")"
sql_star="*"
sql_eq="="
sql_neq="!="
sql_lt="<"
sql_gt=">"
sql_lte="<="
sql_gte=">="
sql_wildcard="%"
sql_single_wild="_"
sql_inject_or="' OR '1'='1"
sql_inject_comment="' --"
sql_inject_union="' UNION SELECT"
sql_true="1=1"
sql_false="1=0"
sql_cast="CAST("
sql_coalesce="COALESCE("
sql_begin="BEGIN"
sql_commit="COMMIT"
sql_rollback="ROLLBACK"
sql_transaction="TRANSACTION"
```

---

## HTTP Dictionary

```
# http.dict -- HTTP methods, headers, status lines, and structural tokens
http_get="GET"
http_post="POST"
http_put="PUT"
http_delete="DELETE"
http_patch="PATCH"
http_head="HEAD"
http_options="OPTIONS"
http_trace="TRACE"
http_connect="CONNECT"
http_version="HTTP/1.1"
http_version10="HTTP/1.0"
http_version20="HTTP/2"
http_crlf="\x0d\x0a"
http_double_crlf="\x0d\x0a\x0d\x0a"
http_sp=" "
http_colon=": "
http_host="Host: "
http_content_type="Content-Type: "
http_content_length="Content-Length: "
http_transfer_encoding="Transfer-Encoding: chunked"
http_connection="Connection: "
http_keep_alive="keep-alive"
http_close="close"
http_accept="Accept: */*"
http_auth="Authorization: Bearer "
http_cookie="Cookie: "
http_set_cookie="Set-Cookie: "
http_user_agent="User-Agent: "
http_referer="Referer: "
http_origin="Origin: "
http_location="Location: "
http_ct_json="application/json"
http_ct_form="application/x-www-form-urlencoded"
http_ct_multi="multipart/form-data"
http_ct_xml="application/xml"
http_ct_html="text/html"
http_ct_plain="text/plain"
http_ct_octet="application/octet-stream"
http_200="HTTP/1.1 200 OK"
http_301="HTTP/1.1 301 Moved Permanently"
http_302="HTTP/1.1 302 Found"
http_400="HTTP/1.1 400 Bad Request"
http_401="HTTP/1.1 401 Unauthorized"
http_403="HTTP/1.1 403 Forbidden"
http_404="HTTP/1.1 404 Not Found"
http_500="HTTP/1.1 500 Internal Server Error"
http_chunk_end="0\x0d\x0a\x0d\x0a"
http_path="/"
http_query="?"
http_fragment="#"
http_amp="&"
http_eq="="
```

---

## TLS Dictionary

```
# tls.dict -- TLS handshake types, extensions, and cipher suite bytes
tls_content_handshake="\x16"
tls_content_alert="\x15"
tls_content_change="\x14"
tls_content_appdata="\x17"
tls_version_10="\x03\x01"
tls_version_11="\x03\x02"
tls_version_12="\x03\x03"
tls_version_13="\x03\x04"
tls_hs_client_hello="\x01"
tls_hs_server_hello="\x02"
tls_hs_certificate="\x0b"
tls_hs_server_key_ex="\x0c"
tls_hs_cert_request="\x0d"
tls_hs_server_done="\x0e"
tls_hs_cert_verify="\x0f"
tls_hs_client_key_ex="\x10"
tls_hs_finished="\x14"
tls_hs_new_session="\x04"
tls_hs_encrypted_ext="\x08"
tls_ext_server_name="\x00\x00"
tls_ext_ec_curves="\x00\x0a"
tls_ext_ec_formats="\x00\x0b"
tls_ext_sig_algs="\x00\x0d"
tls_ext_alpn="\x00\x10"
tls_ext_sct="\x00\x12"
tls_ext_key_share="\x00\x33"
tls_ext_supported_ver="\x00\x2b"
tls_ext_psk_modes="\x00\x2d"
tls_ext_pre_shared="\x00\x29"
tls_cipher_aes128_gcm="\x13\x01"
tls_cipher_aes256_gcm="\x13\x02"
tls_cipher_chacha20="\x13\x03"
tls_alert_close="\x00"
tls_alert_unexpected="\x0a"
tls_alert_bad_record="\x14"
tls_alert_handshake_fail="\x28"
tls_alert_bad_cert="\x2a"
tls_alert_decode_err="\x32"
tls_alpn_h2="h2"
tls_alpn_http11="http/1.1"
tls_sni_type="\x00"
```

---

## PNG Dictionary

```
# png.dict -- PNG magic bytes, chunk types, and structural tokens
png_magic="\x89PNG\x0d\x0a\x1a\x0a"
png_ihdr="IHDR"
png_plte="PLTE"
png_idat="IDAT"
png_iend="IEND"
png_chrm="cHRM"
png_gama="gAMA"
png_iccp="iCCP"
png_sbit="sBIT"
png_srgb="sRGB"
png_bkgd="bKGD"
png_hist="hIST"
png_trns="tRNS"
png_phys="pHYs"
png_splt="sPLT"
png_time="tIME"
png_itxt="iTXt"
png_text="tEXt"
png_ztxt="zTXt"
png_actl="acTL"
png_fctl="fcTL"
png_fdat="fdAT"
png_exif="eXIf"
png_colortype_gray="\x00"
png_colortype_rgb="\x02"
png_colortype_palette="\x03"
png_colortype_gray_alpha="\x04"
png_colortype_rgba="\x06"
png_bitdepth_8="\x08"
png_bitdepth_16="\x10"
png_compression="\x00"
png_filter="\x00"
png_interlace_none="\x00"
png_interlace_adam7="\x01"
png_chunk_len_zero="\x00\x00\x00\x00"
png_iend_full="\x00\x00\x00\x00IEND\xae\x42\x60\x82"
```

---

## ELF Dictionary

```
# elf.dict -- ELF magic bytes, section and segment types
elf_magic="\x7fELF"
elf_class32="\x01"
elf_class64="\x02"
elf_data_le="\x01"
elf_data_be="\x02"
elf_version="\x01"
elf_osabi_sysv="\x00"
elf_osabi_linux="\x03"
elf_type_none="\x00\x00"
elf_type_rel="\x01\x00"
elf_type_exec="\x02\x00"
elf_type_dyn="\x03\x00"
elf_type_core="\x04\x00"
elf_machine_386="\x03\x00"
elf_machine_amd64="\x3e\x00"
elf_machine_arm="\x28\x00"
elf_machine_aarch64="\xb7\x00"
elf_machine_riscv="\xf3\x00"
elf_sht_null="\x00\x00\x00\x00"
elf_sht_progbits="\x01\x00\x00\x00"
elf_sht_symtab="\x02\x00\x00\x00"
elf_sht_strtab="\x03\x00\x00\x00"
elf_sht_rela="\x04\x00\x00\x00"
elf_sht_hash="\x05\x00\x00\x00"
elf_sht_dynamic="\x06\x00\x00\x00"
elf_sht_note="\x07\x00\x00\x00"
elf_sht_nobits="\x08\x00\x00\x00"
elf_sht_rel="\x09\x00\x00\x00"
elf_sht_dynsym="\x0b\x00\x00\x00"
elf_pt_null="\x00\x00\x00\x00"
elf_pt_load="\x01\x00\x00\x00"
elf_pt_dynamic="\x02\x00\x00\x00"
elf_pt_interp="\x03\x00\x00\x00"
elf_pt_note="\x04\x00\x00\x00"
elf_pt_phdr="\x06\x00\x00\x00"
elf_pt_tls="\x07\x00\x00\x00"
elf_shstrtab=".shstrtab"
elf_text=".text"
elf_data=".data"
elf_bss=".bss"
elf_rodata=".rodata"
elf_symtab=".symtab"
elf_strtab=".strtab"
elf_dynamic=".dynamic"
elf_got=".got"
elf_plt=".plt"
elf_interp=".interp"
```

---

## WASM Dictionary

```
# wasm.dict -- WebAssembly magic bytes, section IDs, types, and opcodes
wasm_magic="\x00asm"
wasm_version="\x01\x00\x00\x00"
wasm_sec_custom="\x00"
wasm_sec_type="\x01"
wasm_sec_import="\x02"
wasm_sec_function="\x03"
wasm_sec_table="\x04"
wasm_sec_memory="\x05"
wasm_sec_global="\x06"
wasm_sec_export="\x07"
wasm_sec_start="\x08"
wasm_sec_element="\x09"
wasm_sec_code="\x0a"
wasm_sec_data="\x0b"
wasm_sec_datacount="\x0c"
wasm_type_i32="\x7f"
wasm_type_i64="\x7e"
wasm_type_f32="\x7d"
wasm_type_f64="\x7c"
wasm_type_v128="\x7b"
wasm_type_funcref="\x70"
wasm_type_externref="\x6f"
wasm_type_func="\x60"
wasm_type_void="\x40"
wasm_op_unreachable="\x00"
wasm_op_nop="\x01"
wasm_op_block="\x02"
wasm_op_loop="\x03"
wasm_op_if="\x04"
wasm_op_else="\x05"
wasm_op_end="\x0b"
wasm_op_br="\x0c"
wasm_op_br_if="\x0d"
wasm_op_br_table="\x0e"
wasm_op_return="\x0f"
wasm_op_call="\x10"
wasm_op_call_indirect="\x11"
wasm_op_drop="\x1a"
wasm_op_select="\x1b"
wasm_op_local_get="\x20"
wasm_op_local_set="\x21"
wasm_op_global_get="\x23"
wasm_op_global_set="\x24"
wasm_op_i32_load="\x28"
wasm_op_i32_store="\x36"
wasm_op_i32_const="\x41"
wasm_op_i64_const="\x42"
wasm_op_f32_const="\x43"
wasm_op_f64_const="\x44"
wasm_op_i32_add="\x6a"
wasm_op_i32_sub="\x6b"
wasm_op_i32_mul="\x6c"
wasm_limit_min="\x00"
wasm_limit_minmax="\x01"
wasm_mut_const="\x00"
wasm_mut_var="\x01"
wasm_export_func="\x00"
wasm_export_table="\x01"
wasm_export_memory="\x02"
wasm_export_global="\x03"
```

---

## PDF Dictionary

```
# pdf.dict -- PDF object delimiters, stream tokens, and structure
pdf_header="%PDF-1.7"
pdf_header_14="%PDF-1.4"
pdf_header_20="%PDF-2.0"
pdf_comment="%"
pdf_binary_marker="%\xe2\xe3\xcf\xd3"
pdf_obj="obj"
pdf_endobj="endobj"
pdf_stream="stream"
pdf_endstream="endstream"
pdf_xref="xref"
pdf_trailer="trailer"
pdf_startxref="startxref"
pdf_eof="%%EOF"
pdf_dict_open="<<"
pdf_dict_close=">>"
pdf_arr_open="["
pdf_arr_close="]"
pdf_name="/"
pdf_string_open="("
pdf_string_close=")"
pdf_hex_open="<"
pdf_hex_close=">"
pdf_null="null"
pdf_true="true"
pdf_false="false"
pdf_r="R"
pdf_n="n"
pdf_f="f"
pdf_type="/Type"
pdf_catalog="/Catalog"
pdf_pages="/Pages"
pdf_page="/Page"
pdf_font="/Font"
pdf_contents="/Contents"
pdf_resources="/Resources"
pdf_mediabox="/MediaBox"
pdf_length="/Length"
pdf_filter="/Filter"
pdf_flate="/FlateDecode"
pdf_ascii85="/ASCII85Decode"
pdf_asciihex="/ASCIIHexDecode"
pdf_lzw="/LZWDecode"
pdf_dct="/DCTDecode"
pdf_jbig2="/JBIG2Decode"
pdf_jpx="/JPXDecode"
pdf_crypt="/Crypt"
pdf_kids="/Kids"
pdf_count="/Count"
pdf_parent="/Parent"
pdf_size="/Size"
pdf_root="/Root"
pdf_info="/Info"
pdf_id="/ID"
pdf_encrypt="/Encrypt"
pdf_prev="/Prev"
pdf_xref_stream="/XRef"
pdf_objstm="/ObjStm"
```

---

## Protobuf Dictionary

```
# protobuf.dict -- Protocol Buffers wire types, varints, and structural tokens
pb_wire_varint="\x00"
pb_wire_64bit="\x01"
pb_wire_length="\x02"
pb_wire_start_group="\x03"
pb_wire_end_group="\x04"
pb_wire_32bit="\x05"
pb_field1_varint="\x08"
pb_field1_length="\x0a"
pb_field1_64bit="\x09"
pb_field1_32bit="\x0d"
pb_field2_varint="\x10"
pb_field2_length="\x12"
pb_field3_varint="\x18"
pb_field3_length="\x1a"
pb_field4_varint="\x20"
pb_field4_length="\x22"
pb_field5_varint="\x28"
pb_field5_length="\x2a"
pb_field10_varint="\x50"
pb_field10_length="\x52"
pb_field15_varint="\x78"
pb_field15_length="\x7a"
pb_field16_varint="\x80\x01"
pb_field16_length="\x82\x01"
pb_varint_0="\x00"
pb_varint_1="\x01"
pb_varint_127="\x7f"
pb_varint_128="\x80\x01"
pb_varint_max32="\xff\xff\xff\xff\x0f"
pb_varint_max64="\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01"
pb_varint_neg1="\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01"
pb_zigzag_neg1="\x01"
pb_zigzag_1="\x02"
pb_zigzag_neg2="\x03"
pb_len_0="\x00"
pb_len_1="\x01"
pb_len_128="\x80\x01"
pb_float_zero="\x00\x00\x00\x00"
pb_float_one="\x00\x00\x80\x3f"
pb_double_zero="\x00\x00\x00\x00\x00\x00\x00\x00"
pb_double_one="\x00\x00\x00\x00\x00\x00\xf0\x3f"
pb_empty_msg=""
pb_nested_field="\x0a\x02\x08\x01"
```

---

## YAML Dictionary

```
# yaml.dict -- YAML structural tokens, anchors, aliases, and tags
yaml_doc_start="---"
yaml_doc_end="..."
yaml_colon=":"
yaml_colon_sp=": "
yaml_dash="- "
yaml_pipe="|"
yaml_gt=">"
yaml_pipe_minus="|-"
yaml_gt_minus=">-"
yaml_pipe_plus="|+"
yaml_gt_plus=">+"
yaml_anchor="&anchor"
yaml_alias="*anchor"
yaml_merge="<<"
yaml_tag_str="!!str"
yaml_tag_int="!!int"
yaml_tag_float="!!float"
yaml_tag_bool="!!bool"
yaml_tag_null="!!null"
yaml_tag_seq="!!seq"
yaml_tag_map="!!map"
yaml_tag_set="!!set"
yaml_tag_omap="!!omap"
yaml_tag_binary="!!binary"
yaml_tag_timestamp="!!timestamp"
yaml_tag_custom="!custom"
yaml_tag_local="!!"
yaml_tag_verbatim="!<tag:yaml.org,2002:str>"
yaml_null_tilde="~"
yaml_null_word="null"
yaml_null_empty=""
yaml_true="true"
yaml_false="false"
yaml_yes="yes"
yaml_no="no"
yaml_on="on"
yaml_off="off"
yaml_flow_map="{"
yaml_flow_map_end="}"
yaml_flow_seq="["
yaml_flow_seq_end="]"
yaml_comment="# "
yaml_indent2="  "
yaml_indent4="    "
yaml_multiline_key="? "
yaml_directive="%YAML 1.2"
yaml_tag_directive="%TAG !"
yaml_inf=".inf"
yaml_neg_inf="-.inf"
yaml_nan=".nan"
yaml_timestamp="2024-01-01T00:00:00Z"
yaml_date="2024-01-01"
```

---

## TOML Dictionary

```
# toml.dict -- TOML structural tokens, types, and datetime formats
toml_section="["
toml_section_close="]"
toml_array_section="[["
toml_array_section_close="]]"
toml_eq=" = "
toml_dot="."
toml_comment="# "
toml_basic_string="\""
toml_literal_string="'"
toml_ml_basic="\"\"\""
toml_ml_literal="'''"
toml_true="true"
toml_false="false"
toml_int_zero="0"
toml_int_pos="42"
toml_int_neg="-17"
toml_int_underscore="1_000"
toml_int_hex="0xDEADBEEF"
toml_int_oct="0o755"
toml_int_bin="0b11010110"
toml_float="3.14"
toml_float_neg="-0.01"
toml_float_exp="5e+22"
toml_float_both="6.626e-34"
toml_inf="inf"
toml_neg_inf="-inf"
toml_nan="nan"
toml_neg_nan="-nan"
toml_datetime="1979-05-27T07:32:00Z"
toml_datetime_offset="1979-05-27T00:32:00-07:00"
toml_datetime_local="1979-05-27T07:32:00"
toml_date="1979-05-27"
toml_time="07:32:00"
toml_inline_table="{ "
toml_inline_table_close=" }"
toml_array="["
toml_array_close="]"
toml_comma=","
toml_newline="\n"
toml_esc_newline="\\n"
toml_esc_tab="\\t"
toml_esc_backslash="\\\\"
toml_esc_quote="\\\""
toml_esc_unicode="\\u0041"
toml_esc_unicode_long="\\U0001F600"
```

---

## CSS Dictionary

```
# css.dict -- CSS selectors, properties, values, and at-rules
css_brace_open="{"
css_brace_close="}"
css_semicolon=";"
css_colon=":"
css_comma=","
css_dot="."
css_hash="#"
css_star="*"
css_gt=">"
css_plus="+"
css_tilde="~"
css_bracket_open="["
css_bracket_close="]"
css_paren_open="("
css_paren_close=")"
css_at_media="@media"
css_at_import="@import"
css_at_keyframes="@keyframes"
css_at_font_face="@font-face"
css_at_supports="@supports"
css_at_layer="@layer"
css_at_container="@container"
css_at_charset="@charset"
css_at_page="@page"
css_important="!important"
css_display="display:"
css_position="position:"
css_color="color:"
css_background="background:"
css_margin="margin:"
css_padding="padding:"
css_border="border:"
css_width="width:"
css_height="height:"
css_font="font:"
css_transform="transform:"
css_transition="transition:"
css_animation="animation:"
css_content="content:"
css_none="none"
css_inherit="inherit"
css_initial="initial"
css_unset="unset"
css_revert="revert"
css_auto="auto"
css_px="px"
css_em="em"
css_rem="rem"
css_percent="%"
css_vh="vh"
css_vw="vw"
css_calc="calc("
css_var="var(--"
css_url="url("
css_rgb="rgb("
css_rgba="rgba("
css_hsl="hsl("
css_linear_gradient="linear-gradient("
css_pseudo_before="::before"
css_pseudo_after="::after"
css_pseudo_hover=":hover"
css_pseudo_focus=":focus"
css_pseudo_nth=":nth-child("
css_pseudo_not=":not("
```

---

## JavaScript Dictionary

```
# javascript.dict -- JS keywords, operators, template syntax, and APIs
js_function="function"
js_var="var "
js_let="let "
js_const="const "
js_return="return"
js_if="if("
js_else="else"
js_for="for("
js_while="while("
js_switch="switch("
js_case="case "
js_break="break"
js_continue="continue"
js_try="try{"
js_catch="catch("
js_finally="finally{"
js_throw="throw"
js_new="new "
js_this="this"
js_class="class "
js_extends="extends"
js_import="import "
js_export="export "
js_default="default"
js_async="async "
js_await="await "
js_yield="yield"
js_arrow="=>"
js_spread="..."
js_template="\`"
js_template_expr="${"
js_template_close="}"
js_typeof="typeof "
js_instanceof="instanceof"
js_in=" in "
js_of=" of "
js_void="void "
js_delete="delete "
js_null="null"
js_undefined="undefined"
js_true="true"
js_false="false"
js_nan="NaN"
js_infinity="Infinity"
js_eq_strict="==="
js_neq_strict="!=="
js_eq_loose="=="
js_neq_loose="!="
js_and="&&"
js_or="||"
js_nullish="??"
js_optional="?."
js_assign="="
js_plus_assign="+="
js_minus_assign="-="
js_regex_open="/"
js_regex_flags="/gi"
js_proto="__proto__"
js_constructor="constructor"
js_prototype="prototype"
js_eval="eval("
js_json_parse="JSON.parse("
js_json_stringify="JSON.stringify("
js_promise="Promise"
js_symbol="Symbol("
js_proxy="new Proxy("
```

---

## SMTP Dictionary

```
# smtp.dict -- SMTP commands, response codes, and protocol tokens
smtp_ehlo="EHLO "
smtp_helo="HELO "
smtp_mail_from="MAIL FROM:<"
smtp_rcpt_to="RCPT TO:<"
smtp_data="DATA"
smtp_rset="RSET"
smtp_vrfy="VRFY "
smtp_expn="EXPN "
smtp_noop="NOOP"
smtp_quit="QUIT"
smtp_help="HELP"
smtp_auth="AUTH "
smtp_auth_login="AUTH LOGIN"
smtp_auth_plain="AUTH PLAIN"
smtp_starttls="STARTTLS"
smtp_crlf="\x0d\x0a"
smtp_dot_crlf="\x0d\x0a.\x0d\x0a"
smtp_220="220 "
smtp_250="250 "
smtp_251="251 "
smtp_354="354 "
smtp_421="421 "
smtp_450="450 "
smtp_451="451 "
smtp_452="452 "
smtp_500="500 "
smtp_501="501 "
smtp_502="502 "
smtp_503="503 "
smtp_504="504 "
smtp_550="550 "
smtp_551="551 "
smtp_552="552 "
smtp_553="553 "
smtp_554="554 "
smtp_size="SIZE="
smtp_8bitmime="8BITMIME"
smtp_pipelining="PIPELINING"
smtp_dsn="DSN"
smtp_angle_open="<"
smtp_angle_close=">"
smtp_at="@"
smtp_dot="."
smtp_colon=":"
smtp_space=" "
smtp_from="From: "
smtp_to="To: "
smtp_subject="Subject: "
smtp_date="Date: "
smtp_mime="MIME-Version: 1.0"
smtp_ct="Content-Type: text/plain"
smtp_boundary="boundary="
```

---

## DNS Dictionary

```
# dns.dict -- DNS record types, query classes, labels, and compression
dns_id="\x00\x01"
dns_flags_query="\x01\x00"
dns_flags_response="\x81\x80"
dns_qdcount_1="\x00\x01"
dns_ancount_0="\x00\x00"
dns_nscount_0="\x00\x00"
dns_arcount_0="\x00\x00"
dns_type_a="\x00\x01"
dns_type_ns="\x00\x02"
dns_type_cname="\x00\x05"
dns_type_soa="\x00\x06"
dns_type_ptr="\x00\x0c"
dns_type_mx="\x00\x0f"
dns_type_txt="\x00\x10"
dns_type_aaaa="\x00\x1c"
dns_type_srv="\x00\x21"
dns_type_any="\x00\xff"
dns_type_caa="\x01\x01"
dns_type_https="\x00\x41"
dns_type_svcb="\x00\x40"
dns_class_in="\x00\x01"
dns_class_ch="\x00\x03"
dns_class_any="\x00\xff"
dns_ptr_compress="\xc0\x0c"
dns_ptr_compress2="\xc0\x00"
dns_label_end="\x00"
dns_label_3="\x03"
dns_label_www="\x03www"
dns_label_com="\x03com"
dns_label_net="\x03net"
dns_label_org="\x03org"
dns_label_io="\x02io"
dns_ttl_0="\x00\x00\x00\x00"
dns_ttl_300="\x00\x00\x01\x2c"
dns_ttl_3600="\x00\x00\x0e\x10"
dns_rdlen_4="\x00\x04"
dns_rdlen_16="\x00\x10"
dns_edns_opt="\x00\x29"
dns_edns_udp_4096="\x10\x00"
dns_rcode_ok="\x00"
dns_rcode_nxdomain="\x03"
dns_rcode_refused="\x05"
dns_max_label="\x3f"
```

---

## Usage Instructions

### Using with cargo-fuzz (libFuzzer)

```bash
# Save the dictionary block you need to a .dict file
# Run with the -dict flag
cargo fuzz run parse_json -- -dict=dictionaries/json.dict

# Combine with other libFuzzer options
cargo fuzz run parse_json -- \
    -dict=dictionaries/json.dict \
    -max_len=4096 \
    -timeout=10
```

### Using with AFL++

```bash
# AFL++ uses -x for dictionary files
afl-fuzz -i corpus/ -o findings/ -x dictionaries/json.dict -- ./target @@

# Multiple dictionaries: concatenate them
cat dictionaries/json.dict dictionaries/http.dict > combined.dict
afl-fuzz -i corpus/ -o findings/ -x combined.dict -- ./target @@
```

### Using with standalone libFuzzer

```bash
# Compile your harness with -fsanitize=fuzzer
clang++ -fsanitize=fuzzer,address -o fuzz_target fuzz_target.cpp

# Run with dictionary
./fuzz_target -dict=dictionaries/xml.dict corpus/
```

### Using with go-fuzz

```bash
# go-fuzz reads dictionary files from the workdir/dict/ directory
mkdir -p workdir/dict
cp dictionaries/json.dict workdir/dict/json.dict

# Run go-fuzz
go-fuzz -bin=./fuzz.zip -workdir=workdir/
```

### Using with bolero (Rust)

```bash
# bolero delegates to libFuzzer or AFL++ under the hood
# For libFuzzer engine, pass dict via BOLERO_LIBFUZZER_ARGS
BOLERO_LIBFUZZER_ARGS="-dict=dictionaries/json.dict" \
    cargo bolero test target_name --engine libfuzzer
```

### Combining Dictionaries

When fuzzing a target that processes multiple formats (e.g., an HTTP server that parses JSON bodies), combine the relevant dictionaries:

```bash
cat dictionaries/http.dict dictionaries/json.dict > combined.dict
```

Avoid combining unrelated dictionaries. A bloated dictionary wastes mutation cycles on irrelevant tokens and slows convergence.

### Creating Your Own Dictionaries

Extract tokens from format specifications, RFCs, or reference implementations:

1. **From specs:** Read the ABNF grammar or BNF and list every terminal symbol.
2. **From source code:** Search for string literals in parsers (`grep -r '"' src/parser/`).
3. **From existing corpora:** Use AFL++'s `afl-cmin` on a corpus, then extract unique byte sequences.
4. **From hex dumps:** For binary formats, use `xxd` on sample files and note recurring byte patterns.

```bash
# Extract string literals from a C parser to seed a dictionary
grep -oP '"[^"]*"' src/parser.c | sort -u | \
    awk '{printf "token_%d=%s\n", NR, $0}' > custom.dict

# Extract tokens from an RFC using keyword patterns
grep -oP '\b[A-Z][A-Z_-]+\b' rfc7230.txt | sort -u | \
    awk '{printf "rfc_%d=\"%s\"\n", NR, $0}' > http_rfc.dict
```

### Dictionary Best Practices

- **Keep dictionaries focused.** One dictionary per format. Combine only when the target genuinely processes multiple formats.
- **Prefer short tokens.** Fuzzers splice dictionary entries into random positions. Long entries reduce the chance of producing valid mutations.
- **Include boundary values.** For numeric formats, include 0, -1, MAX_INT, MIN_INT, NaN, Infinity.
- **Include both valid and near-valid tokens.** Slightly malformed tokens (truncated UTF-8, unclosed delimiters) help find error-handling bugs.
- **Update dictionaries as you learn.** If coverage stalls, inspect the target for new keywords or magic values the fuzzer has not discovered, and add them.

---

## GraphQL Dictionary

```
# graphql.dict -- GraphQL introspection, query syntax, and structural tokens
gql_lbrace="{"
gql_rbrace="}"
gql_lparen="("
gql_rparen=")"
gql_lbracket="["
gql_rbracket="]"
gql_colon=":"
gql_comma=","
gql_bang="!"
gql_dollar="$"
gql_at="@"
gql_ellipsis="..."
gql_eq="="
gql_pipe="|"
gql_hash="#"
gql_query="query"
gql_mutation="mutation"
gql_subscription="subscription"
gql_fragment="fragment"
gql_on="on"
gql_true="true"
gql_false="false"
gql_null="null"
gql_schema="__schema"
gql_type="__type"
gql_typename="__typename"
gql_type_kind="__TypeKind"
gql_directive="__Directive"
gql_enum_value="__EnumValue"
gql_input_value="__InputValue"
gql_field="__Field"
gql_skip="@skip"
gql_include="@include"
gql_deprecated="@deprecated"
gql_skip_if="@skip(if: true)"
gql_include_if="@include(if: false)"
gql_alias="alias:"
gql_inline_frag="... on"
gql_var_def="($var: String)"
gql_var_ref="$var"
gql_introspect_query="{ __schema { types { name } } }"
gql_deep_nest="{ a { b { c { d { e { f { g { h { i { j } } } } } } } } } }"
gql_string="\"\""
gql_block_string="\"\"\"\"\"\""
gql_int="0"
gql_float="0.0"
gql_directive_loc="QUERY"
gql_directive_loc2="MUTATION"
gql_directive_loc3="FIELD"
gql_type_name="String"
gql_type_name2="Int"
gql_type_name3="Float"
gql_type_name4="Boolean"
gql_type_name5="ID"
gql_list_type="[String]"
gql_non_null="String!"
```

---

## JWT Dictionary

```
# jwt.dict -- JWT header fields, algorithms, claims, and attack patterns
jwt_dot="."
jwt_alg="\"alg\""
jwt_typ="\"typ\""
jwt_kid="\"kid\""
jwt_jku="\"jku\""
jwt_x5u="\"x5u\""
jwt_x5c="\"x5c\""
jwt_cty="\"cty\""
jwt_typ_jwt="\"JWT\""
jwt_alg_hs256="\"HS256\""
jwt_alg_hs384="\"HS384\""
jwt_alg_hs512="\"HS512\""
jwt_alg_rs256="\"RS256\""
jwt_alg_rs384="\"RS384\""
jwt_alg_rs512="\"RS512\""
jwt_alg_es256="\"ES256\""
jwt_alg_es384="\"ES384\""
jwt_alg_es512="\"ES512\""
jwt_alg_ps256="\"PS256\""
jwt_alg_ps384="\"PS384\""
jwt_alg_ps512="\"PS512\""
jwt_alg_none="\"none\""
jwt_alg_none_upper="\"None\""
jwt_alg_none_caps="\"NONE\""
jwt_alg_none_mixed="\"nOnE\""
jwt_iss="\"iss\""
jwt_sub="\"sub\""
jwt_aud="\"aud\""
jwt_exp="\"exp\""
jwt_nbf="\"nbf\""
jwt_iat="\"iat\""
jwt_jti="\"jti\""
jwt_b64_pad="="
jwt_b64_pad2="=="
jwt_b64_plus="+"
jwt_b64_slash="/"
jwt_b64_minus="-"
jwt_b64_underscore="_"
jwt_empty_sig="."
jwt_header_hs256="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
jwt_header_none="eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0"
jwt_empty_obj="e30"
jwt_attack_none="{\"alg\":\"none\",\"typ\":\"JWT\"}"
jwt_attack_empty_sig="{\"alg\":\"none\"}"
jwt_lbrace="{"
jwt_rbrace="}"
jwt_colon=":"
jwt_comma=","
jwt_exp_zero="\"exp\":0"
jwt_exp_max="\"exp\":9999999999"
jwt_nbf_future="\"nbf\":9999999999"
```

---

## Where to Put Dictionaries

Store dictionaries in a consistent location relative to your project root. Recommended directory structure:

```
project/
├── fuzz/
│   ├── dictionaries/          # Preferred location for Rust (cargo-fuzz)
│   │   ├── json.dict
│   │   ├── xml.dict
│   │   └── custom.dict
│   ├── corpus/
│   │   └── my_target/
│   └── fuzz_targets/
│       └── my_target.rs
├── dictionaries/              # Alternative: top-level for polyglot projects
│   ├── json.dict
│   └── http.dict
└── tests/
    └── fuzz/
        └── dictionaries/      # Alternative: under test directory
```

**Guidelines:**

- **Rust (cargo-fuzz):** `fuzz/dictionaries/` -- keeps dictionaries alongside targets and corpora.
- **C/C++ (AFL++/libFuzzer):** `dictionaries/` at project root or alongside the fuzzing Makefile.
- **Go:** `testdata/fuzz/dictionaries/` -- follows Go convention of `testdata/` for test fixtures.
- **Python (Atheris/Hypothesis):** `tests/fuzz/dictionaries/` -- under the test tree.
- **TypeScript (fast-check/Jazzer.js):** `tests/fuzz/dictionaries/` or `__tests__/fuzz/dictionaries/`.
- **CI/OSS-Fuzz:** Reference dictionaries in your `project.yaml` or build script with an absolute path from the project root.
- **Commit dictionaries to version control.** They are small text files and should evolve alongside the code.
- **Name files after the format**, not the target: `json.dict`, `xml.dict`, `graphql.dict` -- this makes them reusable across targets.
