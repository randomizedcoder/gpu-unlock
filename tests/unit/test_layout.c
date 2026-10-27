// SPDX-License-Identifier: GPL-2.0-only
/* layout_610.c: the WPR layout carved down from the top of the framebuffer. */
#include "table.h"

#include "layout_610.h"

#define SUITE "gpu_unlock_layout"

/* 8 GiB of framebuffer with the VGA workspace in its last MiB. */
#define FB 0x200000000ull
#define VGA 0x1fff00000ull
#define FRTS 0x100000ull
#define BOOT 0x20000ull
#define IMAGE 0x2000000ull
#define NONWPR 0x100000ull
#define HEAP 0x8000000ull

#define LAYOUT(fb, vga, lock_valid, lock_low, frts, boot, image, nonwpr, heap) \
	{ fb, vga, lock_valid, lock_low, frts, boot, image, nonwpr, heap }
#define VALID LAYOUT(FB, VGA, false, 0, FRTS, BOOT, IMAGE, NONWPR, HEAP)

static void test_inputs(void)
{
	static const struct {
		const char *description;
		struct gpu_unlock_layout_in in;
		int expected;
		u64 wpr_end;
	} rows[] = {
		{ "positive: the WPR ends at the VGA base", VALID, 0, VGA },
		{ "positive: an MMU lock below the VGA base lowers the WPR end",
		  LAYOUT(FB, VGA, true, 0x1ffe80000, FRTS, BOOT, IMAGE, NONWPR, HEAP),
		  0, 0x1ffe80000 },
		{ "negative: no usable framebuffer",
		  LAYOUT(0, VGA, false, 0, FRTS, BOOT, IMAGE, NONWPR, HEAP), -EINVAL, 0 },
		{ "negative: no VGA base",
		  LAYOUT(FB, 0, false, 0, FRTS, BOOT, IMAGE, NONWPR, HEAP), -EINVAL, 0 },
		{ "negative: no FRTS size",
		  LAYOUT(FB, VGA, false, 0, 0, BOOT, IMAGE, NONWPR, HEAP), -EINVAL, 0 },
		{ "negative: no boot size",
		  LAYOUT(FB, VGA, false, 0, FRTS, 0, IMAGE, NONWPR, HEAP), -EINVAL, 0 },
		{ "negative: no image size",
		  LAYOUT(FB, VGA, false, 0, FRTS, BOOT, 0, NONWPR, HEAP), -EINVAL, 0 },
		{ "negative: a VGA base below 128 KiB",
		  LAYOUT(FB, 0x1ffff, false, 0, FRTS, BOOT, IMAGE, NONWPR, HEAP), -EINVAL, 0 },
		{ "negative: FRTS larger than the space below the WPR end",
		  LAYOUT(FB, VGA, false, 0, VGA + 1, BOOT, IMAGE, NONWPR, HEAP), -ERANGE, 0 },
		{ "negative: an image larger than the space below the boot region",
		  LAYOUT(FB, VGA, false, 0, FRTS, BOOT, VGA, NONWPR, HEAP), -ERANGE, 0 },
		{ "negative: a heap larger than the space below the image",
		  LAYOUT(FB, VGA, false, 0, FRTS, BOOT, IMAGE, NONWPR, 0x1fe000000), -ERANGE, 0 },
		{ "boundary: a VGA base off 128 KiB rounds the WPR end down",
		  LAYOUT(FB, VGA + 0x1ffff, false, 0, FRTS, BOOT, IMAGE, NONWPR, HEAP), 0, VGA },
		{ "boundary: usable framebuffer ending at the WPR end",
		  LAYOUT(VGA, VGA, false, 0, FRTS, BOOT, IMAGE, NONWPR, HEAP), 0, VGA },
		{ "boundary: usable framebuffer one byte short of the WPR end",
		  LAYOUT(VGA - 1, VGA, false, 0, FRTS, BOOT, IMAGE, NONWPR, HEAP), -ERANGE, 0 },
		{ "corner: an MMU lock above the VGA base is ignored",
		  LAYOUT(FB, VGA, true, 0x1fff80000, FRTS, BOOT, IMAGE, NONWPR, HEAP), 0, VGA },
		{ "corner: an MMU lock that is not valid is ignored",
		  LAYOUT(FB, VGA, false, 0x1ffe80000, FRTS, BOOT, IMAGE, NONWPR, HEAP), 0, VGA },
		{ "corner: a heap request that overflows rounding up",
		  LAYOUT(FB, VGA, false, 0, FRTS, BOOT, IMAGE, NONWPR, ~0ull), -EOVERFLOW, 0 },
		{ "corner: a non-WPR size that overflows rounding up",
		  LAYOUT(FB, VGA, false, 0, FRTS, BOOT, IMAGE, ~0ull, HEAP), -EOVERFLOW, 0 },
	};
	struct gpu_unlock_layout_out out;
	char description[128];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		memset(&out, 0, sizeof(out));
		table_err(SUITE, rows[i].description, rows[i].expected,
			  gpu_unlock_layout(&rows[i].in, &out));
		if (rows[i].expected)
			continue;
		snprintf(description, sizeof(description), "%s: wpr_end", rows[i].description);
		table_hex(SUITE, description, rows[i].wpr_end, out.wpr_end);
	}
}

/* Each region of the valid layout, worked by hand from the top down. */
static void test_regions(void)
{
	static const struct gpu_unlock_layout_in in = VALID;
	static const struct gpu_unlock_layout_in odd =
		LAYOUT(FB, VGA, false, 0, FRTS, BOOT + 0x800, IMAGE + 0x1000, NONWPR, HEAP);
	struct gpu_unlock_layout_out out = { 0 };
	int ret = gpu_unlock_layout(&in, &out);
	const struct {
		const char *description;
		u64 expected, got;
	} rows[] = {
		{ "positive: reserved top is the VGA base", VGA, out.reserved_top },
		{ "positive: FRTS sits just below the WPR end", 0x1ffe00000, out.frts_offset },
		{ "positive: the boot region sits below FRTS", 0x1ffde0000, out.boot_offset },
		{ "positive: the image sits below the boot region, 64 KiB aligned",
		  0x1fdde0000, out.gsp_offset },
		{ "positive: the heap sits below the image, 1 MiB aligned", 0x1f5d00000,
		  out.heap_offset },
		{ "positive: the heap size is the request", HEAP, out.heap_size },
		{ "positive: the WPR starts 1 MiB of metadata below the heap", 0x1f5c00000,
		  out.wpr_start },
		{ "positive: non-WPR sits just below the WPR", 0x1f5b00000, out.nonwpr_start },
	};
	size_t i;

	table_err(SUITE, "positive: the valid layout", 0, ret);
	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_hex(SUITE, rows[i].description, rows[i].expected, rows[i].got);
	/* Sizes off the alignment round each region's start down. */
	gpu_unlock_layout(&odd, &out);
	table_hex(SUITE, "boundary: a boot region 2 KiB over starts on the 4 KiB below",
		  0x1ffddf000, out.boot_offset);
	table_hex(SUITE, "boundary: an image 4 KiB over starts on the 64 KiB below",
		  0x1fddd0000, out.gsp_offset);
	table_err(SUITE, "negative: no input", -EINVAL, gpu_unlock_layout(NULL, &out));
	table_err(SUITE, "negative: no output", -EINVAL, gpu_unlock_layout(&in, NULL));
}

void test_layout(void)
{
	test_inputs();
	test_regions();
}
