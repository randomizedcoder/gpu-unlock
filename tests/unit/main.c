// SPDX-License-Identifier: GPL-2.0-only
#include "table.h"

int table_failed;

int main(void)
{
	test_recipes();
	test_payload();
	test_gfw_eval();
	if (table_failed)
		printf("%d rows failed\n", table_failed);
	return table_failed ? 1 : 0;
}
