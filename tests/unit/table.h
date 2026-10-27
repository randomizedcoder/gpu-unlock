/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Table-driven host tests for the gpu_unlock helpers that touch no
 * hardware. Each suite walks a table of rows, each with a description
 * ("positive:", "negative:", "boundary:" or "corner:") and an expected
 * value, and reports every row as
 *
 *   PASS  description  (expected X, got Y)
 *
 * as the Nix eval tests and the analysis gate do.
 */
#ifndef GPU_UNLOCK_TEST_TABLE_H
#define GPU_UNLOCK_TEST_TABLE_H

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

extern int table_rows, table_failed;

static inline void table_report(const char *suite, const char *description,
				bool pass, const char *expected, const char *got)
{
	table_rows++;
	if (!pass)
		table_failed++;
	printf("%s  %s, %s  (expected %s, got %s)\n", pass ? "PASS" : "FAIL",
	       suite, description, expected, got);
}

/* The errnos the helpers return, by name, so a row reads as the code does. */
static inline const char *table_errname(int ret)
{
	static char other[16];

	switch (ret) {
	case 0: return "0";
	case -EINVAL: return "-EINVAL";
	case -ERANGE: return "-ERANGE";
	case -EOVERFLOW: return "-EOVERFLOW";
	case -ENOENT: return "-ENOENT";
	case -EAGAIN: return "-EAGAIN";
	case -ENODEV: return "-ENODEV";
	case -EOPNOTSUPP: return "-EOPNOTSUPP";
	}
	snprintf(other, sizeof(other), "%d", ret);
	return other;
}

static inline void table_err(const char *suite, const char *description,
			     int expected, int got)
{
	char e[16], g[16];

	snprintf(e, sizeof(e), "%s", table_errname(expected));
	snprintf(g, sizeof(g), "%s", table_errname(got));
	table_report(suite, description, expected == got, e, g);
}

static inline void table_hex(const char *suite, const char *description,
			     unsigned long long expected, unsigned long long got)
{
	char e[24], g[24];

	snprintf(e, sizeof(e), "%#llx", expected);
	snprintf(g, sizeof(g), "%#llx", got);
	table_report(suite, description, expected == got, e, g);
}

static inline void table_dec(const char *suite, const char *description,
			     unsigned long long expected, unsigned long long got)
{
	char e[24], g[24];

	snprintf(e, sizeof(e), "%llu", expected);
	snprintf(g, sizeof(g), "%llu", got);
	table_report(suite, description, expected == got, e, g);
}

static inline void table_bool(const char *suite, const char *description,
			      bool expected, bool got)
{
	table_report(suite, description, expected == got,
		     expected ? "true" : "false", got ? "true" : "false");
}

static inline void table_str(const char *suite, const char *description,
			     const char *expected, const char *got)
{
	table_report(suite, description,
		     expected == got || (expected && got && !strcmp(expected, got)),
		     expected ? expected : "NULL", got ? got : "NULL");
}

/* Little-endian fields in the synthetic images the parser rows build. */
static inline void table_put(unsigned char *p, unsigned int width,
			     unsigned long long value)
{
	unsigned int i;

	for (i = 0; i < width; i++)
		p[i] = (unsigned char)(value >> (8 * i));
}

static inline unsigned long long table_get(const unsigned char *p, unsigned int width)
{
	unsigned long long value = 0;
	unsigned int i;

	for (i = 0; i < width; i++)
		value |= (unsigned long long)p[i] << (8 * i);
	return value;
}

void test_recipes(void);
void test_payload(void);
void test_gfw_eval(void);
void test_layout(void);
void test_prep(void);
void test_vbios(void);

#endif
