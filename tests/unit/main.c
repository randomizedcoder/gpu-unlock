// SPDX-License-Identifier: GPL-2.0-only
#include "table.h"

int table_rows, table_failed;

int main(void)
{
	test_recipes();
	test_payload();
	test_gfw_eval();
	test_layout();
	test_prep();
	test_vbios();
	/* An empty run tests nothing, so it must not pass. */
	if (!table_rows) {
		printf("FAIL  no rows ran\n");
		return 1;
	}
	if (table_failed)
		printf("%d rows failed\n", table_failed);
	return table_failed ? 1 : 0;
}
