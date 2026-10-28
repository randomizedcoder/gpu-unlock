// SPDX-License-Identifier: GPL-2.0-only
/*
 * vbios_610.c: finding the FWSEC descriptor in a VBIOS ROM, picking its
 * signature, and patching the FRTS command into its DMEM.
 */
#include "table.h"

#include "vbios_610.h"

#define SUITE_ROM "gpu_unlock_vbios_fwsec"

/*
 * A 2 KiB ROM of one PCI image, every structure at a fixed place:
 *   0x000 image signature 0xaa55, PCIR pointer at 0x18
 *   0x020 PCIR: image length 4 * 512 bytes (the whole ROM), code type 0, last
 *   0x100 BIT header: size 12, token stride 6, one token
 *   0x10c falcon ucode token ('p', version 2), pointer to 0x120
 *   0x120 the ucode table offset, 0x140
 *   0x140 ucode table: version 1, 6-byte header and entries, one entry
 *   0x146 the entry: app 0x85 (FWSEC), descriptor at 0x200
 *   0x200 v3 descriptor, 44 bytes and one 384-byte signature, then the
 *         0x400-byte image at 0x3ac: 0x100 of IMEM, then 0x200 of DMEM
 */
#define ROM_SIZE 0x800
#define BIT 0x100
#define DESC 0x200
#define DESC_SIZE (44 + 384)

static void build_rom(u8 *rom)
{
	unsigned int i, sum = 0;

	memset(rom, 0, ROM_SIZE);
	table_put(rom, 2, 0xaa55);
	table_put(rom + 0x18, 2, 0x20);
	memcpy(rom + 0x20, "PCIR", 4);
	table_put(rom + 0x2a, 2, 0x18);
	table_put(rom + 0x30, 2, 4);
	rom[0x35] = 0x80;

	table_put(rom + BIT, 2, 0xb8ff);
	memcpy(rom + BIT + 2, "BIT", 4);
	rom[BIT + 8] = 12;
	rom[BIT + 9] = 6;
	rom[BIT + 10] = 1;
	for (i = 0; i < 11; i++)
		sum += rom[BIT + i];
	rom[BIT + 11] = (u8)-sum;
	rom[BIT + 12] = 0x70;
	rom[BIT + 13] = 2;
	table_put(rom + BIT + 14, 2, 4);
	table_put(rom + BIT + 16, 2, 0x120);

	table_put(rom + 0x120, 4, 0x140);
	rom[0x140] = 1;
	rom[0x141] = 6;
	rom[0x142] = 6;
	rom[0x143] = 1;
	rom[0x146] = 0x85;
	table_put(rom + 0x148, 4, DESC);

	table_put(rom + DESC, 4, 1 | 3 << 8 | DESC_SIZE << 16);
	table_put(rom + DESC + 4, 4, 0x400);
	table_put(rom + DESC + 12, 4, 0x10);
	table_put(rom + DESC + 20, 4, 0x100);
	table_put(rom + DESC + 32, 4, 0x200);
	table_put(rom + DESC + 36, 2, 0x400);
	rom[DESC + 38] = 9;
	rom[DESC + 39] = 1;
	table_put(rom + DESC + 40, 2, 0x1);
}

static void test_rom(void)
{
	static const struct {
		const char *description;
		unsigned int at, width;
		u32 value;
		size_t length;
		int expected;
	} rows[] = {
		{ "positive: the FWSEC descriptor", 0, 0, 0, ROM_SIZE, 0 },
		{ "positive: a VN image signature", 0, 2, 0x4e56, ROM_SIZE, 0 },
		{ "positive: an NPDS data structure", 0x20, 4, 0x5344504e, ROM_SIZE, 0 },
		{ "negative: no image signature", 0, 2, 0, ROM_SIZE, -EINVAL },
		{ "negative: no PCIR", 0x20, 4, 0, ROM_SIZE, -EINVAL },
		{ "negative: image length 0", 0x30, 2, 0, ROM_SIZE, -EINVAL },
		{ "negative: a BIT header whose checksum fails is skipped", BIT + 6, 1, 1,
		  ROM_SIZE, -ENOENT },
		{ "negative: no FWSEC entry in the ucode table", 0x146, 1, 0x45, ROM_SIZE,
		  -ENOENT },
		{ "negative: ucode table version 2", 0x140, 1, 2, ROM_SIZE, -EOPNOTSUPP },
		{ "negative: ucode table entries under 6 bytes", 0x142, 1, 5, ROM_SIZE,
		  -EOPNOTSUPP },
		{ "negative: descriptor version 4", DESC + 1, 1, 4, ROM_SIZE, -EOPNOTSUPP },
		{ "negative: descriptor without bit 0", DESC, 1, 0, ROM_SIZE, -EOPNOTSUPP },
		{ "negative: no stored image size", DESC + 4, 4, 0, ROM_SIZE, -EINVAL },
		{ "negative: no engine", DESC + 36, 2, 0, ROM_SIZE, -EINVAL },
		{ "negative: ucode id 0", DESC + 38, 1, 0, ROM_SIZE, -EINVAL },
		{ "negative: signature count disagrees with the versions", DESC + 39, 1, 2,
		  ROM_SIZE, -EINVAL },
		{ "boundary: ucode id 16", DESC + 38, 1, 16, ROM_SIZE, 0 },
		{ "boundary: ucode id 17", DESC + 38, 1, 17, ROM_SIZE, -EINVAL },
		{ "boundary: descriptor size 43", DESC + 2, 2, 43, ROM_SIZE, -EOPNOTSUPP },
		{ "boundary: image length one block past the ROM", 0x30, 2, 5, ROM_SIZE,
		  -EINVAL },
		{ "boundary: a ROM one byte shorter than its image length", 0, 0, 0,
		  ROM_SIZE - 1, -EINVAL },
		{ "boundary: an image that rounds up past the ROM", DESC + 4, 4, 0x401,
		  ROM_SIZE, -EINVAL },
		{ "boundary: DMEM ending at the end of the image", DESC + 32, 4, 0x300,
		  ROM_SIZE, 0 },
		{ "boundary: DMEM one byte past the image", DESC + 32, 4, 0x301, ROM_SIZE,
		  -EINVAL },
		{ "boundary: interface in the last dword of DMEM", DESC + 12, 4, 0x1fc,
		  ROM_SIZE, 0 },
		{ "boundary: interface one byte past DMEM", DESC + 12, 4, 0x1fd, ROM_SIZE,
		  -EINVAL },
		{ "boundary: PKC signature ending at the end of DMEM", DESC + 8, 4, 0x80,
		  ROM_SIZE, 0 },
		{ "boundary: PKC signature one byte past DMEM", DESC + 8, 4, 0x81, ROM_SIZE,
		  -EINVAL },
		{ "corner: a ROM over 1 MiB, refused before it is read", 0, 0, 0,
		  (1 << 20) + 1, -EINVAL },
		{ "corner: an image not marked last with nothing after it", 0x35, 1, 0,
		  ROM_SIZE, -EINVAL },
		{ "corner: a ucode token pointing past the ROM", BIT + 16, 2, 0x7fd, ROM_SIZE,
		  -EINVAL },
		{ "corner: a descriptor at the end of the ROM", 0x148, 4, ROM_SIZE, ROM_SIZE,
		  -EINVAL },
		{ "corner: a descriptor offset that wraps", 0x148, 4, 0xffffffff, ROM_SIZE,
		  -EINVAL },
	};
	struct gpu_unlock_fwsec fw;
	u8 rom[ROM_SIZE];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		build_rom(rom);
		table_put(rom + rows[i].at, rows[i].width, rows[i].value);
		table_err(SUITE_ROM, rows[i].description, rows[i].expected,
			  gpu_unlock_vbios_fwsec(rom, rows[i].length, &fw));
	}

	build_rom(rom);
	gpu_unlock_vbios_fwsec(rom, ROM_SIZE, &fw);
	{
		const struct {
			const char *description;
			u32 expected, got;
		} fields[] = {
			{ "positive: version 3", 3, fw.version },
			{ "positive: the image follows the descriptor", DESC + DESC_SIZE,
			  fw.image_off },
			{ "positive: the stored image size", 0x400, fw.image_size },
			{ "positive: DMEM follows IMEM in the image", 0x100, fw.data_off },
			{ "positive: the DMEM size", 0x200, fw.dmem_size },
			{ "positive: the signature follows the 44-byte header", DESC + 44,
			  fw.sig_off },
			{ "positive: one 384-byte signature", 384, fw.sig_bytes },
			{ "positive: the ucode id", 9, fw.ucode_id },
		};

		for (i = 0; i < ARRAY_SIZE(fields); i++)
			table_hex(SUITE_ROM, fields[i].description, fields[i].expected,
				  fields[i].got);
	}
	table_err(SUITE_ROM, "negative: no ROM", -EINVAL,
		  gpu_unlock_vbios_fwsec(NULL, ROM_SIZE, &fw));
	table_err(SUITE_ROM, "negative: no output", -EINVAL,
		  gpu_unlock_vbios_fwsec(rom, ROM_SIZE, NULL));
}

/*
 * The ROM inside an NVGI version-3 container, as the PROM window shows
 * it: the flash base at 0x10 is 0, so the RFRD directory is at 0x1000,
 * and it points to the image at 0x1100.
 */
#define BOX_IMAGE 0x1100
#define BOX_SIZE (BOX_IMAGE + ROM_SIZE)

static void build_box(u8 *box)
{
	memset(box, 0, BOX_SIZE);
	memcpy(box, "NVGI", 4);
	table_put(box + 4, 4, 3 << 8);
	table_put(box + 8, 4, 0x10);
	memcpy(box + 0x1000, "RFRD", 4);
	table_put(box + 0x1008, 4, BOX_IMAGE);
	build_rom(box + BOX_IMAGE);
}

static void test_container(void)
{
	static const struct {
		const char *description;
		unsigned int at;
		u32 value;
		int expected;
	} rows[] = {
		{ "positive: a ROM in an NVGI container", 0, 0x4947564e, 0 },
		{ "negative: container version 2", 4, 2 << 8, -EOPNOTSUPP },
		{ "negative: no RFRD directory", 0x1000, 0, -EINVAL },
		{ "negative: an image offset of 0", 0x1008, 0, -EINVAL },
		{ "negative: no image signature at the image offset", 0x1008, BOX_IMAGE + 4,
		  -EINVAL },
		{ "corner: an image offset not 4-byte aligned", 0x1008, BOX_IMAGE + 2,
		  -EINVAL },
		{ "corner: a flash base putting the directory past the container", 0x10,
		  0x1000, -EINVAL },
	};
	struct gpu_unlock_fwsec fw;
	static u8 box[BOX_SIZE];
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		build_box(box);
		table_put(box + rows[i].at, 4, rows[i].value);
		table_err(SUITE_ROM, rows[i].description, rows[i].expected,
			  gpu_unlock_vbios_fwsec(box, BOX_SIZE, &fw));
	}

	build_box(box);
	gpu_unlock_vbios_fwsec(box, BOX_SIZE, &fw);
	table_hex(SUITE_ROM, "positive: the image offset counts from the container",
		  BOX_IMAGE + DESC + DESC_SIZE, fw.image_off);
	table_hex(SUITE_ROM, "positive: the signature offset counts from the container",
		  BOX_IMAGE + DESC + 44, fw.sig_off);
}

#define SUITE_SIG "gpu_unlock_fwsec_sig_offset"

static void test_sig_offset(void)
{
	static const struct {
		const char *description;
		u32 versions, fuse, sig_size;
		int expected;
		u32 offset;
	} rows[] = {
		{ "positive: the only version", 0x1, 0, 384, 0, 0 },
		{ "positive: the third of three versions", 0x7, 2, 384, 0, 768 },
		{ "positive: only versions present below the fuse count", 0x5, 2, 384, 0, 384 },
		{ "negative: the fuse version is not present", 0x2, 0, 384, -ERANGE, 0 },
		{ "negative: no signature size", 0x1, 0, 0, -EINVAL, 0 },
		{ "boundary: fuse version 15", 0xffff, 15, 384, 0, 15 * 384 },
		{ "boundary: fuse version 16", 0xffff, 16, 384, -EINVAL, 0 },
		{ "boundary: a version above bit 15", 0x10001, 0, 384, -EINVAL, 0 },
		{ "boundary: the largest offset that fits", 0xffff, 15, 0x11111111, 0,
		  0xffffffff },
		{ "boundary: a signature one byte larger overflows", 0xffff, 15, 0x11111112,
		  -EOVERFLOW, 0 },
		{ "corner: the first version, whatever the signature size", 0x1, 0, ~0u, 0, 0 },
	};
	char description[128];
	u32 offset;
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		offset = 0;
		table_err(SUITE_SIG, rows[i].description, rows[i].expected,
			  gpu_unlock_fwsec_sig_offset(rows[i].versions, rows[i].fuse,
						      rows[i].sig_size, &offset));
		if (rows[i].expected)
			continue;
		snprintf(description, sizeof(description), "%s: offset", rows[i].description);
		table_dec(SUITE_SIG, description, rows[i].offset, offset);
	}
	table_err(SUITE_SIG, "negative: no output", -EINVAL,
		  gpu_unlock_fwsec_sig_offset(0x1, 0, 384, NULL));
}

#define SUITE_FRTS "gpu_unlock_fwsec_patch_frts"

/*
 * A 0x400-byte image with 0x200 of DMEM at 0x100. The interface table at
 * DMEM 0 has two 8-byte entries: id 1, then id 4, the mapper, at 0x80.
 * The V3 mapper's 44-byte command buffer is at 0x100.
 */
#define FRTS 0x1ffe00000ull

static const struct gpu_unlock_fwsec frts_fw = {
	.image_size = 0x400, .data_off = 0x100, .dmem_size = 0x200,
	.interface_off = 0,
};

static void build_dmem(u8 *image)
{
	u8 *dmem = image + frts_fw.data_off;

	memset(image, 0, frts_fw.image_size);
	dmem[0] = 1;
	dmem[1] = 4;
	dmem[2] = 8;
	dmem[3] = 2;
	table_put(dmem + 4, 4, 1);
	table_put(dmem + 8, 4, 0x40);
	table_put(dmem + 12, 4, 4);
	table_put(dmem + 16, 4, 0x80);
	table_put(dmem + 0x84, 2, 3);
	table_put(dmem + 0x86, 2, 64);
	table_put(dmem + 0x88, 4, 0x100);
	table_put(dmem + 0x8c, 4, 44);
}

static void test_patch_frts(void)
{
	static const struct {
		const char *description;
		unsigned int at, width;
		u32 value;
		u64 frts;
		int expected;
	} rows[] = {
		{ "positive: the FRTS command is written", 0, 0, 0, FRTS, 0 },
		{ "negative: no FRTS offset", 0, 0, 0, 0, -EINVAL },
		{ "negative: FRTS not 4 KiB aligned", 0, 0, 0, FRTS + 0x800, -EINVAL },
		{ "negative: interface version 2", 0, 1, 2, FRTS, -EOPNOTSUPP },
		{ "negative: interface entries of 4 bytes", 2, 1, 4, FRTS, -EOPNOTSUPP },
		{ "negative: one interface entry", 3, 1, 1, FRTS, -EINVAL },
		{ "negative: no mapper entry", 12, 4, 5, FRTS, -ENOENT },
		{ "negative: two mapper entries", 4, 4, 4, FRTS, -EINVAL },
		{ "negative: mapper version 2", 0x84, 2, 2, FRTS, -EOPNOTSUPP },
		{ "negative: a mapper under 64 bytes", 0x86, 2, 63, FRTS, -EOPNOTSUPP },
		{ "negative: a command buffer under 44 bytes", 0x8c, 4, 43, FRTS, -EINVAL },
		{ "boundary: FRTS in the highest page a dword can hold", 0, 0, 0,
		  0xffffffffull << 12, 0 },
		{ "boundary: FRTS one page higher", 0, 0, 0, 0x100000000ull << 12, -EINVAL },
		{ "boundary: a command ending at the end of DMEM", 0x88, 4, 0x200 - 44, FRTS, 0 },
		{ "boundary: a command one byte past DMEM", 0x88, 4, 0x200 - 43, FRTS, -EINVAL },
		{ "boundary: a mapper one byte past DMEM", 16, 4, 0x200 - 63, FRTS, -EINVAL },
		{ "corner: interface entries running past DMEM", 3, 1, 255, FRTS, -EINVAL },
	};
	struct gpu_unlock_fwsec fw;
	u8 image[0x400];
	const u8 *dmem = image + frts_fw.data_off;
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		build_dmem(image);
		table_put(image + frts_fw.data_off + rows[i].at, rows[i].width, rows[i].value);
		table_err(SUITE_FRTS, rows[i].description, rows[i].expected,
			  gpu_unlock_fwsec_patch_frts(image, &frts_fw, rows[i].frts));
	}

	build_dmem(image);
	gpu_unlock_fwsec_patch_frts(image, &frts_fw, FRTS);
	table_hex(SUITE_FRTS, "positive: command version 1", 1, table_get(dmem + 0x100, 4));
	table_hex(SUITE_FRTS, "positive: the FRTS page", FRTS >> 12,
		  table_get(dmem + 0x100 + 32, 4));
	table_hex(SUITE_FRTS, "positive: the FRTS size in pages", 0x100,
		  table_get(dmem + 0x100 + 36, 4));
	table_hex(SUITE_FRTS, "positive: the mapper command is FRTS (0x15)", 0x15,
		  table_get(dmem + 0x80 + 44, 4));
	table_hex(SUITE_FRTS, "corner: nothing written after the command", 0,
		  dmem[0x100 + 44]);

	fw = frts_fw;
	fw.dmem_size = 0x301;
	table_err(SUITE_FRTS, "boundary: DMEM one byte past the image", -EINVAL,
		  gpu_unlock_fwsec_patch_frts(image, &fw, FRTS));
	fw = frts_fw;
	fw.interface_off = 0x1fd;
	table_err(SUITE_FRTS, "boundary: interface one byte past DMEM", -EINVAL,
		  gpu_unlock_fwsec_patch_frts(image, &fw, FRTS));
	table_err(SUITE_FRTS, "negative: no image", -EINVAL,
		  gpu_unlock_fwsec_patch_frts(NULL, &frts_fw, FRTS));
	table_err(SUITE_FRTS, "negative: no descriptor", -EINVAL,
		  gpu_unlock_fwsec_patch_frts(image, NULL, FRTS));
}

void test_vbios(void)
{
	test_rom();
	test_container();
	test_sig_offset();
	test_patch_frts();
}
