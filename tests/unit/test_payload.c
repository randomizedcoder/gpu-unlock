// SPDX-License-Identifier: GPL-2.0-only
/* payload.c: checking a Booter DMEM payload and building its image. */
#include "table.h"

#include "payload.h"

#define SUITE_CHECK "gu_payload_check"
#define SUITE_BUILD "gu_payload_build"
#define CANARY 0xa5

static const struct gu_payload_word word8[] = { { 8, 0x11111111 } };
static const struct gu_payload_word word12[] = { { 12, 0x11111111 } };
static const struct gu_payload_word word13[] = { { 13, 0x11111111 } };
static const struct gu_payload_word word0[] = { { 0, 0x11111111 } };

/* A 16-byte payload with fill 0xdeadbeef. The valid one has the value
 * slot at 0, the address slot at 4 and one baked word at 8.
 */
#define PAYLOAD(size, value_off, address_off, words, count) \
	{ "test", size, 0xdeadbeef, value_off, address_off, words, count, \
	  GU_PAYLOAD_HALT_RESET_PLM }
#define VALID PAYLOAD(16, 0, 4, word8, 1)

static u32 read_word(const u8 *image, u32 offset)
{
	return image[offset] | image[offset + 1] << 8 |
	       image[offset + 2] << 16 | (u32)image[offset + 3] << 24;
}

static void test_check(void)
{
	static const struct {
		const char *description;
		struct gu_payload payload;
		int expected;
	} rows[] = {
		{ "positive: a valid payload", VALID, 0 },
		{ "positive: no baked words", PAYLOAD(16, 0, 4, NULL, 0), 0 },
		{ "negative: no name", { NULL, 16, 0xdeadbeef, 0, 4, word8, 1,
					 GU_PAYLOAD_HALT_RESET_PLM }, -EINVAL },
		{ "negative: size 0", PAYLOAD(0, 0, 4, word8, 1), -EINVAL },
		{ "negative: words missing for word_count 1", PAYLOAD(16, 0, 4, NULL, 1), -EINVAL },
		{ "boundary: one dword, both slots at 0",
		  PAYLOAD(4, 0, 0, NULL, 0), 0 },
		{ "boundary: value slot in the last dword", PAYLOAD(16, 12, 4, word8, 1), 0 },
		{ "boundary: value slot one byte past the last dword", PAYLOAD(16, 13, 4, word8, 1), -EINVAL },
		{ "boundary: address slot in the last dword", PAYLOAD(16, 0, 12, word8, 1), 0 },
		{ "boundary: address slot one byte past the last dword", PAYLOAD(16, 0, 13, word8, 1), -EINVAL },
		{ "boundary: baked word in the last dword", PAYLOAD(16, 0, 4, word12, 1), 0 },
		{ "boundary: baked word one byte past the last dword", PAYLOAD(16, 0, 4, word13, 1), -EINVAL },
		{ "corner: size not a whole number of dwords", PAYLOAD(18, 0, 4, word8, 1), -EINVAL },
		{ "corner: size below one dword", PAYLOAD(2, 0, 0, NULL, 0), -EINVAL },
		{ "corner: the largest offset, 0xffffffff", PAYLOAD(16, ~0u, 4, word8, 1), -EINVAL },
	};
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_err(SUITE_CHECK, rows[i].description, rows[i].expected,
			  gu_payload_check(&rows[i].payload));
	table_err(SUITE_CHECK, "negative: no payload", -EINVAL, gu_payload_check(NULL));
}

static void test_build(void)
{
	static const struct gu_payload valid = VALID;
	static const struct gu_payload overlap = PAYLOAD(16, 0, 4, word0, 1);
	static const struct gu_payload invalid = PAYLOAD(18, 0, 4, word8, 1);
	static const struct {
		const char *description;
		u32 offset, expected;
	} rows[] = {
		{ "positive: the value slot holds the value", 0, 0xffffffff },
		{ "positive: the address slot holds the address", 4, 0x823804 },
		{ "positive: the baked word is in place", 8, 0x11111111 },
		{ "positive: every other dword is the fill", 12, 0xdeadbeef },
	};
	u8 image[20];
	size_t i;

	memset(image, CANARY, sizeof(image));
	table_err(SUITE_BUILD, "positive: builds", 0,
		  gu_payload_build(&valid, image, 0x823804, 0xffffffff));
	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_hex(SUITE_BUILD, rows[i].description, rows[i].expected,
			  read_word(image, rows[i].offset));
	table_hex(SUITE_BUILD, "boundary: nothing written past size", CANARY, image[16]);
	table_hex(SUITE_BUILD, "corner: little-endian, low address byte first", 0x04, image[4]);

	table_err(SUITE_BUILD, "corner: a baked word under the value slot still builds", 0,
		  gu_payload_build(&overlap, image, 0x823804, 0x22222222));
	table_hex(SUITE_BUILD, "corner: the value slot wins over a baked word at its offset",
		  0x22222222, read_word(image, 0));

	memset(image, CANARY, sizeof(image));
	table_err(SUITE_BUILD, "negative: an invalid payload", -EINVAL,
		  gu_payload_build(&invalid, image, 0, 0));
	table_hex(SUITE_BUILD, "negative: an invalid payload writes nothing", CANARY, image[0]);
	table_err(SUITE_BUILD, "negative: no image", -EINVAL,
		  gu_payload_build(&valid, NULL, 0, 0));
}

void test_payload(void)
{
	test_check();
	test_build();
}
