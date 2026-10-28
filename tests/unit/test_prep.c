// SPDX-License-Identifier: GPL-2.0-only
/*
 * prep_610.c: the Booter signature patch, the ELF section lookup, the
 * radix table plan and pages, the boot descriptor parse, the WPR
 * metadata and the small register helpers.
 */
#include <stddef.h>

#include "table.h"

#include "prep_610.h"

static void test_fuse_version(void)
{
	static const struct {
		const char *description;
		u32 raw, expected;
	} rows[] = {
		{ "positive: bit 0 is version 1", 0x1, 1 },
		{ "positive: the highest set bit counts", 0x3, 2 },
		{ "positive: bit 4 is version 5", 0x10, 5 },
		{ "negative: no fuse burnt is version 0", 0x0, 0 },
		{ "boundary: bit 15, the top of the field, is version 16", 0x8000, 16 },
		{ "boundary: bit 16 is outside the field", 0x10000, 0 },
		{ "corner: all-ones is version 16", 0xffffffff, 16 },
		{ "corner: bits above the field are ignored", 0xffff0001, 1 },
	};
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_dec("gpu_unlock_fuse_version", rows[i].description, rows[i].expected,
			  gpu_unlock_fuse_version(rows[i].raw));
}

static void test_dma_cmd(void)
{
	static const struct {
		const char *description;
		bool imem, secure;
		u32 expected;
	} rows[] = {
		{ "positive: DMEM, 256-byte transfer", false, false, 0x600 },
		{ "positive: IMEM", true, false, 0x610 },
		{ "positive: secure IMEM", true, true, 0x614 },
		{ "corner: secure is ignored for DMEM", false, true, 0x600 },
	};
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_hex("gpu_unlock_dma_cmd", rows[i].description, rows[i].expected,
			  gpu_unlock_dma_cmd(rows[i].imem, rows[i].secure));
}

#define SUITE_BOOTER "gpu_unlock_booter_patch"

/* A 16-byte image; signature n is four bytes of n. */
static void test_booter_patch(void)
{
	static const u8 signatures[12] = { 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3 };
	static const struct {
		const char *description;
		u32 num_apps, num_sigs, hdr_bytes, patch_loc, sig_bytes, fuse;
		int expected;
		u8 patched;
	} rows[] = {
		{ "positive: fuse 0 takes the last of two signatures", 1, 2, 8, 8, 8, 0, 0, 2 },
		{ "positive: fuse 1 takes the first of two signatures", 1, 2, 8, 8, 8, 1, 0, 1 },
		{ "positive: fuse 0 takes the last of three signatures", 1, 3, 12, 8, 12, 0, 0, 3 },
		{ "negative: two apps", 2, 2, 8, 8, 8, 0, -EINVAL, 0 },
		{ "negative: no signatures", 1, 0, 8, 8, 8, 0, -EINVAL, 0 },
		{ "negative: signature bytes differ from the header", 1, 2, 8, 8, 12, 0, -EINVAL, 0 },
		{ "negative: signature bytes do not split evenly", 1, 3, 8, 8, 8, 0, -EINVAL, 0 },
		{ "boundary: fuse equal to the signature count", 1, 2, 8, 8, 8, 2, -ERANGE, 0 },
		{ "boundary: patch in the last four bytes", 1, 2, 8, 12, 8, 0, 0, 2 },
		{ "boundary: patch one byte past the image", 1, 2, 8, 13, 8, 0, -EINVAL, 0 },
		{ "corner: one signature, whatever the fuse", 1, 1, 8, 8, 8, 5, 0, 1 },
		{ "corner: no signature bytes", 1, 1, 0, 8, 0, 0, -EINVAL, 0 },
		{ "corner: the largest patch location", 1, 2, 8, ~0u, 8, 0, -EINVAL, 0 },
	};
	struct gpu_unlock_booter_hdr hdr = { 0 };
	char description[128];
	u8 image[16];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		memset(image, 0, sizeof(image));
		hdr.num_apps = rows[i].num_apps;
		hdr.num_sigs = rows[i].num_sigs;
		hdr.sig_bytes = rows[i].hdr_bytes;
		hdr.patch_loc = rows[i].patch_loc;
		table_err(SUITE_BOOTER, rows[i].description, rows[i].expected,
			  gpu_unlock_booter_patch(image, sizeof(image), &hdr, signatures,
						  rows[i].sig_bytes, rows[i].fuse));
		if (rows[i].expected)
			continue;
		snprintf(description, sizeof(description), "%s: patched byte",
			 rows[i].description);
		table_dec(SUITE_BOOTER, description, rows[i].patched, image[rows[i].patch_loc]);
	}
	table_err(SUITE_BOOTER, "negative: no image", -EINVAL,
		  gpu_unlock_booter_patch(NULL, 16, &hdr, signatures, 8, 0));
	table_err(SUITE_BOOTER, "negative: no header", -EINVAL,
		  gpu_unlock_booter_patch(image, 16, NULL, signatures, 8, 0));
	table_err(SUITE_BOOTER, "negative: no signatures", -EINVAL,
		  gpu_unlock_booter_patch(image, 16, &hdr, NULL, 8, 0));
}

#define SUITE_ELF "gpu_unlock_elf_section"

/*
 * A 384-byte ELF64: the header, a string table at 64, and four section
 * headers at 128 (null, .shstrtab, .fwimage at 96, .fwdata from 128 to
 * the end of the file).
 */
#define ELF_SIZE 384
#define SH(i) (128 + 64 * (i))
static const char strings[] = "\0.shstrtab\0.fwimage\0.fwdata";

static void build_elf(u8 *elf)
{
	memset(elf, 0, ELF_SIZE);
	memcpy(elf, "\x7f" "ELF", 4);
	elf[4] = 2;
	elf[5] = 1;
	elf[6] = 1;
	table_put(elf + 20, 4, 1);
	table_put(elf + 40, 8, SH(0));
	table_put(elf + 52, 2, 64);
	table_put(elf + 58, 2, 64);
	table_put(elf + 60, 2, 4);
	table_put(elf + 62, 2, 1);
	memcpy(elf + 64, strings, sizeof(strings));
	table_put(elf + SH(1), 4, 1);
	table_put(elf + SH(1) + 24, 8, 64);
	table_put(elf + SH(1) + 32, 8, sizeof(strings));
	table_put(elf + SH(2), 4, 11);
	table_put(elf + SH(2) + 24, 8, 96);
	table_put(elf + SH(2) + 32, 8, 16);
	table_put(elf + SH(3), 4, 20);
	table_put(elf + SH(3) + 24, 8, 128);
	table_put(elf + SH(3) + 32, 8, 256);
}

static void test_elf_section(void)
{
	static const struct {
		const char *description;
		const char *name;
		unsigned int at, width;
		u64 value;
		size_t length;
		int expected;
		u64 offset;
	} rows[] = {
		{ "positive: .fwimage", ".fwimage", 0, 0, 0, ELF_SIZE, 0, 96 },
		{ "positive: .shstrtab itself", ".shstrtab", 0, 0, 0, ELF_SIZE, 0, 64 },
		{ "negative: a name not in the file", ".missing", 0, 0, 0, ELF_SIZE, -ENOENT, 0 },
		{ "negative: bad magic", ".fwimage", 1, 1, 'X', ELF_SIZE, -EINVAL, 0 },
		{ "negative: 32-bit ELF", ".fwimage", 4, 1, 1, ELF_SIZE, -EINVAL, 0 },
		{ "negative: big-endian ELF", ".fwimage", 5, 1, 2, ELF_SIZE, -EINVAL, 0 },
		{ "negative: a section header size of 40", ".fwimage", 58, 2, 40, ELF_SIZE,
		  -EINVAL, 0 },
		{ "negative: no sections", ".fwimage", 60, 2, 0, ELF_SIZE, -EINVAL, 0 },
		{ "boundary: a section ending at the end of the file", ".fwdata", 0, 0, 0,
		  ELF_SIZE, 0, 128 },
		{ "boundary: a section one byte past the end of the file", ".fwdata",
		  SH(3) + 32, 8, 257, ELF_SIZE, -EINVAL, 0 },
		{ "boundary: section headers one byte past the end of the file", ".fwimage",
		  40, 8, SH(0) + 1, ELF_SIZE, -EINVAL, 0 },
		{ "boundary: a file one byte shorter than the ELF header", ".fwimage", 0, 0, 0,
		  63, -EINVAL, 0 },
		{ "boundary: string table index equal to the section count", ".fwimage",
		  62, 2, 4, ELF_SIZE, -EINVAL, 0 },
		{ "boundary: a name offset at the end of the string table", ".fwimage",
		  SH(2), 4, sizeof(strings), ELF_SIZE, -EINVAL, 0 },
		{ "corner: a string table without its last NUL", ".fwimage", SH(1) + 32, 8,
		  sizeof(strings) - 1, ELF_SIZE, -EINVAL, 0 },
		{ "corner: a name in two sections", ".fwimage", SH(3), 4, 11, ELF_SIZE,
		  -EINVAL, 0 },
		{ "corner: a prefix of a name is not the name", ".fw", 0, 0, 0, ELF_SIZE,
		  -ENOENT, 0 },
		{ "corner: a longer name is not the name", ".fwimage2", 0, 0, 0, ELF_SIZE,
		  -ENOENT, 0 },
		{ "corner: a section offset that wraps", ".fwimage", SH(2) + 24, 8, ~0ull,
		  ELF_SIZE, -EINVAL, 0 },
	};
	struct gpu_unlock_span span;
	char description[128];
	u8 elf[ELF_SIZE];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		build_elf(elf);
		table_put(elf + rows[i].at, rows[i].width, rows[i].value);
		memset(&span, 0, sizeof(span));
		table_err(SUITE_ELF, rows[i].description, rows[i].expected,
			  gpu_unlock_elf_section(elf, rows[i].length, rows[i].name, &span));
		if (rows[i].expected)
			continue;
		snprintf(description, sizeof(description), "%s: offset", rows[i].description);
		table_dec(SUITE_ELF, description, rows[i].offset, span.offset);
	}
	build_elf(elf);
	table_err(SUITE_ELF, "negative: no ELF", -EINVAL,
		  gpu_unlock_elf_section(NULL, ELF_SIZE, ".fwimage", &span));
	table_err(SUITE_ELF, "negative: no name", -EINVAL,
		  gpu_unlock_elf_section(elf, ELF_SIZE, NULL, &span));
	table_err(SUITE_ELF, "negative: no span", -EINVAL,
		  gpu_unlock_elf_section(elf, ELF_SIZE, ".fwimage", NULL));
}

#define SUITE_PLAN "gpu_unlock_radix_plan"

static void test_radix_plan(void)
{
	static const struct {
		const char *description;
		u64 size;
		int expected;
		u64 table_pages, data_bytes;
	} rows[] = {
		{ "positive: one byte needs one page per level", 1, 0, 3, 0x1000 },
		{ "positive: one page", 0x1000, 0, 3, 0x1000 },
		{ "negative: size 0", 0, -EINVAL, 0, 0 },
		{ "boundary: one byte over a page rounds up", 0x1001, 0, 3, 0x2000 },
		{ "boundary: 2 MiB fills one leaf table", 0x200000, 0, 3, 0x200000 },
		{ "boundary: 2 MiB + 1 needs a second leaf table", 0x200001, 0, 4, 0x201000 },
		{ "boundary: 512 GiB, all one root page maps", 1ull << 39, 0, 1 + 512 + 262144,
		  1ull << 39 },
		{ "boundary: 512 GiB + 1 needs a second root page", (1ull << 39) + 1, -ERANGE,
		  0, 0 },
		{ "corner: the largest size that rounds up without overflow",
		  ~0ull - 0xfff, -ERANGE, 0, 0 },
		{ "corner: a size that overflows rounding up", ~0ull - 0xffe, -EOVERFLOW, 0, 0 },
	};
	struct gpu_unlock_radix_plan plan;
	char description[128];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		table_err(SUITE_PLAN, rows[i].description, rows[i].expected,
			  gpu_unlock_radix_plan(rows[i].size, &plan));
		if (rows[i].expected)
			continue;
		snprintf(description, sizeof(description), "%s: table pages",
			 rows[i].description);
		table_dec(SUITE_PLAN, description, rows[i].table_pages, plan.table_pages);
		snprintf(description, sizeof(description), "%s: data bytes",
			 rows[i].description);
		table_hex(SUITE_PLAN, description, rows[i].data_bytes, plan.data_bytes);
	}
	table_err(SUITE_PLAN, "negative: no plan", -EINVAL, gpu_unlock_radix_plan(1, NULL));
}

#define SUITE_PAGE "gpu_unlock_radix_page"

static void test_radix_page(void)
{
	static const u64 children[513] = { 0x1000, 0x123456789000 };
	static const u64 unaligned[] = { 0x1000, 0x1001 };
	static const struct {
		const char *description;
		const u64 *children;
		size_t count;
		int expected;
	} rows[] = {
		{ "positive: two children", children, 2, 0 },
		{ "negative: no children", children, 0, -EINVAL },
		{ "negative: a child not 4 KiB aligned", unaligned, 2, -EINVAL },
		{ "boundary: 512 children fill the page", children, 512, 0 },
		{ "boundary: 513 children", children, 513, -EINVAL },
	};
	static u8 page[GU_RADIX_PAGE];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_err(SUITE_PAGE, rows[i].description, rows[i].expected,
			  gpu_unlock_radix_page(page, rows[i].children, rows[i].count));

	memset(page, 0xa5, sizeof(page));
	gpu_unlock_radix_page(page, children, 2);
	table_hex(SUITE_PAGE, "positive: the first child, little-endian", 0x1000,
		  table_get(page, 8));
	table_hex(SUITE_PAGE, "positive: the second child", 0x123456789000,
		  table_get(page + 8, 8));
	table_hex(SUITE_PAGE, "corner: the rest of the page is cleared", 0,
		  table_get(page + GU_RADIX_PAGE - 8, 8));

	memset(page, 0xa5, sizeof(page));
	gpu_unlock_radix_page(page, unaligned, 2);
	table_hex(SUITE_PAGE, "negative: a refused page writes nothing", 0xa5, page[0]);
	table_err(SUITE_PAGE, "negative: no page", -EINVAL,
		  gpu_unlock_radix_page(NULL, children, 2));
	table_err(SUITE_PAGE, "negative: no children array", -EINVAL,
		  gpu_unlock_radix_page(page, NULL, 2));
}

#define SUITE_DESC "gpu_unlock_boot_desc_parse"

/*
 * An 84-byte version-5 descriptor for a 4 KiB image, as dwords. Each
 * range is (offset, size): dwords 1-2, 3-4, 8-9 (manifest), 10-11
 * (data) and 12-13 (code, which ends at the end of the image).
 */
#define DESC_IMAGE 0x1000

static void build_desc(u8 *desc)
{
	static const u32 dwords[21] = {
		[0] = 5, [1] = 0, [2] = 0x100, [3] = 0x100, [4] = 0x100,
		[8] = 0x200, [9] = 0x100, [10] = 0x300, [11] = 0x100,
		[12] = 0x400, [13] = 0xc00, [14] = 1, [19] = DESC_IMAGE,
	};
	size_t i;

	memset(desc, 0, 88);
	for (i = 0; i < ARRAY_SIZE(dwords); i++)
		table_put(desc + i * 4, 4, dwords[i]);
}

static void test_boot_desc(void)
{
	static const struct {
		const char *description;
		int dword;
		u32 value;
		size_t size;
		u32 image_size;
		int expected;
	} rows[] = {
		{ "positive: a version-5 descriptor", -1, 0, 84, DESC_IMAGE, 0 },
		{ "negative: version 4", 0, 4, 84, DESC_IMAGE, -EINVAL },
		{ "negative: dword 14 is not 1", 14, 2, 84, DESC_IMAGE, -EINVAL },
		{ "negative: image size differs from the image", 19, 0x2000, 84, DESC_IMAGE,
		  -EINVAL },
		{ "negative: dword 20 set", 20, 1, 84, DESC_IMAGE, -EINVAL },
		{ "negative: image size 0", 19, 0, 84, 0, -EINVAL },
		{ "negative: a range of size 0", 2, 0, 84, DESC_IMAGE, -ERANGE },
		{ "negative: a secure partition (dword 5)", 5, 1, 84, DESC_IMAGE, -EOPNOTSUPP },
		{ "negative: ITCM (dword 7)", 7, 1, 84, DESC_IMAGE, -EOPNOTSUPP },
		{ "negative: dword 15 set", 15, 1, 84, DESC_IMAGE, -EOPNOTSUPP },
		{ "negative: SMP (dword 18)", 18, 1, 84, DESC_IMAGE, -EOPNOTSUPP },
		{ "boundary: 80 bytes", -1, 0, 80, DESC_IMAGE, -EINVAL },
		{ "boundary: 88 bytes", -1, 0, 88, DESC_IMAGE, -EINVAL },
		{ "boundary: code one byte past the image", 13, 0xc01, 84, DESC_IMAGE, -ERANGE },
		{ "boundary: code starting at the end of the image", 12, DESC_IMAGE, 84,
		  DESC_IMAGE, -ERANGE },
		{ "corner: a range whose end wraps", 13, 0xffffffff, 84, DESC_IMAGE, -ERANGE },
	};
	struct gpu_unlock_boot_desc out;
	u8 desc[88];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		build_desc(desc);
		if (rows[i].dword >= 0)
			table_put(desc + rows[i].dword * 4, 4, rows[i].value);
		table_err(SUITE_DESC, rows[i].description, rows[i].expected,
			  gpu_unlock_boot_desc_parse(desc, rows[i].size, rows[i].image_size,
						     &out));
	}

	build_desc(desc);
	memset(&out, 0, sizeof(out));
	gpu_unlock_boot_desc_parse(desc, 84, DESC_IMAGE, &out);
	table_hex(SUITE_DESC, "positive: manifest offset from dword 8", 0x200,
		  out.manifest_offset);
	table_hex(SUITE_DESC, "positive: data offset from dword 10", 0x300, out.data_offset);
	table_hex(SUITE_DESC, "positive: code offset from dword 12", 0x400, out.code_offset);
	table_err(SUITE_DESC, "negative: no descriptor", -EINVAL,
		  gpu_unlock_boot_desc_parse(NULL, 84, DESC_IMAGE, &out));
	table_err(SUITE_DESC, "negative: no output", -EINVAL,
		  gpu_unlock_boot_desc_parse(desc, 84, DESC_IMAGE, NULL));
}

#define SUITE_META "gpu_unlock_wpr_meta_pack"

/* The layout test_layout.c works out for 8 GiB, and arguments that fit it. */
static const struct gpu_unlock_layout_out layout = {
	.reserved_top = 0x1fff00000, .wpr_end = 0x1fff00000,
	.frts_offset = 0x1ffe00000, .boot_offset = 0x1ffde0000,
	.gsp_offset = 0x1fdde0000, .heap_offset = 0x1f5d00000,
	.heap_size = 0x8000000, .wpr_start = 0x1f5c00000,
	.nonwpr_start = 0x1f5b00000,
};
static const struct gpu_unlock_wpr_args args = {
	.fb_size = 0x200000000, .vga_offset = 0x1fff00000, .frts_size = 0x100000,
	.signature_dma = 0x10000, .signature_size = 0x1000,
	.radix_dma = 0x20000, .image_size = 0x2000000, .boot_dma = 0x30000,
	.boot = { .code_offset = 0x400, .data_offset = 0x300,
		  .manifest_offset = 0x200, .image_size = 0x1000 },
};

/* A row changes one u64 field, of the layout or of the arguments. */
#define ARG(field) offsetof(struct gpu_unlock_wpr_args, field), false
#define LAY(field) offsetof(struct gpu_unlock_layout_out, field), true

static void test_wpr_meta(void)
{
	static const struct {
		const char *description;
		size_t field;
		bool in_layout;
		u64 value;
		int expected;
	} rows[] = {
		{ "positive: arguments that fit the layout", ARG(radix_dma), 0x20000, 0 },
		{ "negative: no signature size", ARG(signature_size), 0, -EINVAL },
		{ "negative: no image size", ARG(image_size), 0, -EINVAL },
		{ "negative: no framebuffer size", ARG(fb_size), 0, -EINVAL },
		{ "negative: FRTS size not the region below the WPR end", ARG(frts_size),
		  0x80000, -EINVAL },
		{ "negative: radix table not 4 KiB aligned", ARG(radix_dma), 0x20800, -EINVAL },
		{ "negative: boot image not 4 KiB aligned", ARG(boot_dma), 0x30001, -EINVAL },
		{ "negative: WPR starting at the non-WPR start", LAY(nonwpr_start), 0x1f5c00000,
		  -EINVAL },
		{ "negative: boot region at FRTS", LAY(boot_offset), 0x1ffe00000, -EINVAL },
		{ "boundary: an image filling its region", ARG(image_size), 0x2000000, 0 },
		{ "boundary: an image one byte over its region", ARG(image_size), 0x2000001,
		  -EINVAL },
		{ "boundary: a heap filling its region", LAY(heap_size), 0x80e0000, 0 },
		{ "boundary: a heap one byte over its region", LAY(heap_size), 0x80e0001,
		  -EINVAL },
		{ "boundary: VGA one byte below the WPR end", ARG(vga_offset), 0x1ffefffff,
		  -EINVAL },
		{ "boundary: VGA at the end of the framebuffer", ARG(fb_size), 0x1fff00000,
		  -EINVAL },
		{ "boundary: framebuffer one byte past VGA", ARG(fb_size), 0x1fff00001, 0 },
	};
	struct gpu_unlock_layout_out l;
	struct gpu_unlock_wpr_args a;
	u8 meta[GU_WPR_META_SIZE];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		l = layout;
		a = args;
		memcpy((u8 *)(rows[i].in_layout ? (void *)&l : (void *)&a) + rows[i].field,
		       &rows[i].value, sizeof(u64));
		table_err(SUITE_META, rows[i].description, rows[i].expected,
			  gpu_unlock_wpr_meta_pack(meta, &l, &a));
	}

	a = args;
	a.boot.code_offset = a.boot.image_size;
	table_err(SUITE_META, "boundary: boot code offset at the end of the boot image",
		  -EINVAL, gpu_unlock_wpr_meta_pack(meta, &layout, &a));
	a.boot.code_offset = a.boot.image_size - 1;
	table_err(SUITE_META, "boundary: boot code offset in the last byte of the boot image",
		  0, gpu_unlock_wpr_meta_pack(meta, &layout, &a));

	memset(meta, 0xa5, sizeof(meta));
	gpu_unlock_wpr_meta_pack(meta, &layout, &args);
	table_hex(SUITE_META, "positive: the magic", GU_WPR_META_MAGIC, table_get(meta, 8));
	table_hex(SUITE_META, "positive: revision 1", 1, table_get(meta + 8, 8));
	table_hex(SUITE_META, "positive: the non-WPR size", 0x100000,
		  table_get(meta + 104, 8));
	table_hex(SUITE_META, "positive: the WPR end", layout.wpr_end,
		  table_get(meta + 168, 8));
	table_hex(SUITE_META, "positive: the VGA workspace size", 0x100000,
		  table_get(meta + 192, 8));
	table_hex(SUITE_META, "corner: the bytes after the last field are cleared", 0,
		  table_get(meta + GU_WPR_META_SIZE - 8, 8));
	table_err(SUITE_META, "negative: no output", -EINVAL,
		  gpu_unlock_wpr_meta_pack(NULL, &layout, &args));
	table_err(SUITE_META, "negative: no layout", -EINVAL,
		  gpu_unlock_wpr_meta_pack(meta, NULL, &args));
	table_err(SUITE_META, "negative: no arguments", -EINVAL,
		  gpu_unlock_wpr_meta_pack(meta, &layout, NULL));
}

void test_prep(void)
{
	test_fuse_version();
	test_dma_cmd();
	test_booter_patch();
	test_elf_section();
	test_radix_plan();
	test_radix_page();
	test_boot_desc();
	test_wpr_meta();
}
