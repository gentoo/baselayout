#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include "debug.h"
#include "simple-regex.h"

char *test_data[] = {
	"ab", "a?[ab]b",
	"abb", "a?[ab]b",
	"aab", "a?[ab]b",
	"a", "a?a?a?a",
	"aa", "a?a?a?a",
	"aa", "a?a?a?aa",
	"aaa", "a?a?a?aa",
	"ab", "[ab]*",
	"abc", "[ab]*.",
	"ab", "[ab]*b+",
	"ab", "a?[ab]*b+",
	NULL
};

int main() {
	regex_data_t tmp_data;
	char buf[256], string[100], regex[100];
	int i;

	for (i = 0; NULL != test_data[i]; i += 2) {
		snprintf(string, 99, "'%s'", test_data[i]);
		snprintf(regex, 99, "'%s'", test_data[i + 1]);
		snprintf(buf, 255, "string = %15s, regex = %15s", string, regex);
		printf("%-70s", buf);
		DO_REGEX(tmp_data, test_data[i], test_data[i + 1], error);
		if (REGEX_MATCH(tmp_data) && (REGEX_FULL_MATCH == tmp_data.match)) {
			printf("%s\n", "[ \033[32;01mOK\033[0m ]");
		} else {
error:
			printf("%s\n", "[ \033[31;01m!!\033[0m ]");
			return 1;
		}
	}

	return 0;
}
