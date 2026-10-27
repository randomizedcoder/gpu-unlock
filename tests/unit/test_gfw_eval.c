// SPDX-License-Identifier: GPL-2.0-only
/*
 * gfw_eval.c: the GFW boot completion test, the PCI command restore and
 * the PMCSR D0 decode.
 */
#include "table.h"

#include "gfw_eval.h"

/* A sample of a card whose GFW has finished: Falcon halted, PLM level 0
 * open, boot status complete.
 */
#define DONE { true, GU_GFW_PLM_LEVEL0, GU_GFW_BOOT_COMPLETED, GU_GFW_CPUCTL_HALTED }

static void test_assess(void)
{
	static const struct {
		const char *description;
		struct gpu_unlock_gfw_sample sample;
		int expected;
	} rows[] = {
		{ "positive: halted, PLM open, boot complete", DONE, 0 },
		{ "positive: only the low byte of boot status counts",
		  { true, 0x1, 0x1ff, 0x10 }, 0 },
		{ "positive: other CPUCTL and PLM bits are ignored",
		  { true, 0xffffff8f, 0xff, 0x30 }, 0 },
		{ "negative: config space did not answer",
		  { false, 0x1, 0xff, 0x10 }, -ENODEV },
		{ "negative: Falcon still running", { true, 0x1, 0xff, 0x0 }, -EAGAIN },
		{ "negative: PLM level 0 still closed", { true, 0x0, 0xff, 0x10 }, -EAGAIN },
		{ "negative: boot status not complete", { true, 0x1, 0xfe, 0x10 }, -EAGAIN },
		{ "boundary: PLM all-ones is no device", { true, ~0u, 0xff, 0x10 }, -ENODEV },
		{ "boundary: boot all-ones is no device", { true, 0x1, ~0u, 0x10 }, -ENODEV },
		{ "boundary: CPUCTL all-ones is no device", { true, 0x1, 0xff, ~0u }, -ENODEV },
		{ "boundary: PLM one bit short of all-ones, level 0 closed",
		  { true, 0xfffffffe, 0xff, 0x10 }, -EAGAIN },
		{ "corner: an all-zero sample is still booting",
		  { true, 0x0, 0x0, 0x0 }, -EAGAIN },
	};
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_err("gpu_unlock_gfw_assess", rows[i].description, rows[i].expected,
			  gpu_unlock_gfw_assess(&rows[i].sample));
	table_err("gpu_unlock_gfw_assess", "corner: no sample", -ENODEV,
		  gpu_unlock_gfw_assess(NULL));
}

static void test_command_restore(void)
{
	static const struct {
		const char *description;
		u16 original, live, expected;
	} rows[] = {
		{ "positive: memory and bus master come back", 0x0006, 0x0000, 0x0006 },
		{ "positive: live bits outside the mask stay", 0x0006, 0x0400, 0x0406 },
		{ "negative: original I/O enable is not copied", 0x0007, 0x0000, 0x0006 },
		{ "negative: bits off in the original are turned off", 0x0000, 0x0006, 0x0000 },
		{ "boundary: original all-ones, live 0", 0xffff, 0x0000, 0x0006 },
		{ "boundary: original 0, live all-ones", 0x0000, 0xffff, 0xfff9 },
		{ "corner: nothing changed since the original", 0x0406, 0x0406, 0x0406 },
	};
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_hex("gpu_unlock_command_restore", rows[i].description, rows[i].expected,
			  gpu_unlock_command_restore(rows[i].original, rows[i].live));
}

static void test_pmcsr_d0(void)
{
	static const struct {
		const char *description;
		u16 pmcsr;
		bool expected;
	} rows[] = {
		{ "positive: D0", 0x0000, true },
		{ "positive: D0 with No_Soft_Reset set", 0x0008, true },
		{ "negative: D1", 0x0001, false },
		{ "negative: D2", 0x0002, false },
		{ "negative: D3hot", 0x0003, false },
		{ "boundary: the lowest bit above the state field", 0x0004, true },
		{ "boundary: every bit but the state field", 0xfffc, true },
		{ "corner: all-ones, config read failed", 0xffff, false },
		{ "corner: D0 with PME_Status and PME_En set", 0x8100, true },
	};
	size_t i;

	for (i = 0; i < ARRAY_SIZE(rows); i++)
		table_bool("gpu_unlock_pmcsr_d0", rows[i].description, rows[i].expected,
			   gpu_unlock_pmcsr_d0(rows[i].pmcsr));
}

void test_gfw_eval(void)
{
	test_assess();
	test_command_restore();
	test_pmcsr_d0();
}
