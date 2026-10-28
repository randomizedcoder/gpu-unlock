// SPDX-License-Identifier: GPL-2.0-only
/*
 * gu_card_find(): the PCI device ID to recipe table in recipes.c,
 * included so the rows can walk its cards[] whatever its length.
 */
#include "table.h"

#include "recipes.c"

#define SUITE "gu_card_find"
#define FW_DIR "gpu-unlock/610.43.03/"

void test_recipes(void)
{
	static const struct {
		const char *description;
		u16 device;
		const char *family;	/* NULL: no card */
		u32 chip;
	} rows[] = {
		{ "positive: RTX 3070 (0x2484)", 0x2484, "GA102/GA103/GA104/GA106", 0x174 },
		{ "positive: RTX 3070 LHR (0x2488)", 0x2488, "GA102/GA103/GA104/GA106", 0x174 },
		{ "positive: RTX 3090 (0x2204) is a GA102", 0x2204, "GA102/GA103/GA104/GA106", 0x172 },
		{ "positive: 0x2414 is a GA103", 0x2414, "GA102/GA103/GA104/GA106", 0x173 },
		{ "positive: RTX 3060 (0x2504) is a GA106", 0x2504, "GA102/GA103/GA104/GA106", 0x176 },
		{ "negative: device ID 0", 0x0000, NULL, 0 },
		{ "negative: all-ones, device not answering", 0xffff, NULL, 0 },
		{ "negative: a Turing card (0x1e04)", 0x1e04, NULL, 0 },
		{ "boundary: 0x2200, the first entry", 0x2200, "GA102/GA103/GA104/GA106", 0x172 },
		{ "boundary: 0x21ff, just below the first entry", 0x21ff, NULL, 0 },
		{ "boundary: 0x2544, the last GA106 entry", 0x2544, "GA102/GA103/GA104/GA106", 0x176 },
		{ "boundary: 0x2545, just above 0x2544", 0x2545, NULL, 0 },
		{ "boundary: 0x2485, the gap between 0x2484 and 0x2486", 0x2485, NULL, 0 },
		/* recipes.c defines the GA100 and AD102 families but no card
		 * entry uses them yet. */
		{ "corner: A100 (0x20b0) has no card entry", 0x20b0, NULL, 0 },
		{ "corner: RTX 4090 (0x2684) has no card entry", 0x2684, NULL, 0 },
	};
	unsigned int i, found = 0, complete = 0;
	char description[96];

	for (i = 0; i < ARRAY_SIZE(rows); i++) {
		const struct gu_card *card = gu_card_find(rows[i].device);

		table_str(SUITE, rows[i].description, rows[i].family,
			  card ? card->family->name : NULL);
		if (card && rows[i].family) {
			snprintf(description, sizeof(description), "%s, PMC_BOOT_0 chip",
				 rows[i].description);
			table_hex(SUITE, description, rows[i].chip, card->chip);
		}
	}

	/* Every entry, looked up by its own ID: a duplicate ID finds the
	 * earlier entry, so the count drops.
	 */
	for (i = 0; i < ARRAY_SIZE(cards); i++) {
		const struct gu_family *family = cards[i].family;

		if (gu_card_find(cards[i].device) == &cards[i])
			found++;
		if (family->fw && family->booter && family->booter->payload &&
		    !strncmp(family->fw->gsp, FW_DIR, strlen(FW_DIR)) &&
		    !strncmp(family->fw->boot, FW_DIR, strlen(FW_DIR)) &&
		    !strncmp(family->fw->desc, FW_DIR, strlen(FW_DIR)) &&
		    !strncmp(family->booter->file, FW_DIR, strlen(FW_DIR)) &&
		    family->privileged.count && family->host.count &&
		    !gu_payload_check(family->booter->payload))
			complete++;
	}
	table_dec(SUITE, "corner: every entry is found by its own ID, so no duplicate IDs",
		  ARRAY_SIZE(cards), found);
	table_dec(SUITE, "corner: every card has firmware, a Booter and a valid payload",
		  ARRAY_SIZE(cards), complete);
}
