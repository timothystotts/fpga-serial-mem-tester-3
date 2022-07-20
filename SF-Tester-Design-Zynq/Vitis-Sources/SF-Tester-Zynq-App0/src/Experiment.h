/**-----------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020 Timothy Stotts
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
------------------------------------------------------------------------------*/
/**-----------------------------------------------------------------------------
-- \file Experiment.h
--
-- \brief A SoPC top-level design with the PMOD SF3 FreeRTOS driver.
-- This design erases a group of subsectors, programs the subsectors, and then
-- byte-compares the contents of the subsectors. The progress is displayed on
-- a PMOD CLS 16x2 dot-matrix LCD and printed on a USB-UART display terminal.
------------------------------------------------------------------------------*/
#ifndef _EXPERIMENT_H_
#define _EXPERIMENT_H_

#include <stdint.h>
#include <stdbool.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"

#define PRINTF_BUF_SZ 34
#define DELAY_10_SECONDS	10000UL
#define DELAY_1_SECOND		1000UL

enum OPERATING_MODE_TAG {
	ST_WAIT_BUTTON_DEP,
	ST_WAIT_BUTTON_REL,
	ST_SET_PATTERN,
	ST_SET_START_ADDR,
	ST_SET_START_WAIT,
	ST_CMD_ERASE_START,
	ST_CMD_ERASE_DONE,
	ST_CMD_PAGE_START,
	ST_CMD_PAGE_DONE,
	ST_CMD_READ_START,
	ST_CMD_READ_DONE,
	ST_DISPLAY_FINAL,
	OPERATING_MODE_NONE
};

enum TEST_PATTERN_TAG {
	TEST_PATTERN_A,
	TEST_PATTERN_B,
	TEST_PATTERN_C,
	TEST_PATTERN_D,
	TEST_PATTERN_NONE
};

typedef struct CLS_LINES_TAG {
	char line1[17];
	char line2[17];
} t_cls_lines;

void Experiment_prvSf3Task( void *pvParameters );

#endif // _EXPERIMENT_H_
