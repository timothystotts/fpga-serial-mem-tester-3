/*------------------------------------------------------------------------------
-- MIT License
--
-- Copyright (c) 2020-2022 Timothy Stotts
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
 * @file Experiment.c
 *
 * @brief A SoPC top-level design with the PMOD SF3 FreeRTOS driver.
 * This design erases a group of subsectors, programs the subsectors, and then
 * byte-compares the contents of the subsectors. The progress is displayed on
 * a PMOD CLS 16x2 dot-matrix LCD and printed on a USB-UART display terminal.
 * The Arty S7-25 LEDs also display status, including progress, PASSED, and DONE.
 *
 * @author
 * Timothy Stotts (timothystotts08@gmail.com)
 *
 * @copyright
 * (c) 2020-2022 Copyright Timothy Stotts
 *
 * This program is free software; distributed under the terms of the MIT
 * License.
------------------------------------------------------------------------------*/

/* FreeRTOS includes. */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "timers.h"
/* Xilinx includes. */
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include "sleep.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xintc.h"
#include "xgpio.h"
/* Project includes. */
#include "PmodSF3.h"
#include "PWM.h"
#include "led_pwm.h"
#include "Experiment.h"

extern QueueHandle_t xQueuePrint;
extern QueueHandle_t xQueueLedConfig;
extern QueueHandle_t xQueueClsDispl;

/* SF3 experiment constants */
#define INTC_DEVICE_ID XPAR_INTC_0_DEVICE_ID

#define USERIO_DEVICE_ID 0
#define SWTCHS_SWS_MASK 0x0F
#define BTNS_SWS_MASK 0x0F
#define SWTCH_SW_CHANNEL 1
#define BTNS_SW_CHANNEL 2
#define SWTCH0_MASK 0x01
#define SWTCH1_MASK 0x02
#define SWTCH2_MASK 0x04
#define SWTCH3_MASK 0x08
#define BTN0_MASK 0x01
#define BTN1_MASK 0x02
#define BTN2_MASK 0x04
#define BTN3_MASK 0x08

/* SF3 state values and flags */
static const uint8_t sf3_test_pattern_startval_a = 0x00;
static const uint8_t sf3_test_pattern_incrval_a = 0x01;
static const uint8_t sf3_test_pattern_startval_b = 0x08;
static const uint8_t sf3_test_pattern_incrval_b = 0x07;
static const uint8_t sf3_test_pattern_startval_c = 0x10;
static const uint8_t sf3_test_pattern_incrval_c = 0x0F;
static const uint8_t sf3_test_pattern_startval_d = 0x18;
static const uint8_t sf3_test_pattern_incrval_d = 0x17;
static const uint32_t max_possible_byte_count = 33554432; // 256 Mbit
static const uint32_t total_iteration_count = 32;
static const uint32_t per_iteration_byte_count = max_possible_byte_count / total_iteration_count;
static const uint32_t last_starting_byte_addr = per_iteration_byte_count * (total_iteration_count - 1);
static const uint32_t sf3_subsector_addr_incr = 4096;
static const uint32_t sf3_page_addr_incr = 256;
static const uint32_t experi_subsector_cnt_per_iter = 8192 / total_iteration_count; // 256 Mbit
static const uint32_t experi_page_cnt_per_iter = 131072 / total_iteration_count; // 256 Mbit
static const uint32_t cnt_t_max = 100 * 3;

typedef struct EXPERIMENT_DATA_TAG {
	/* Driver objects */
	XGpio axGpio;
	/* LED driver palettes stored */
	t_rgb_led_palette_silk ledUpdate[N_COLOR_LEDS/3 + N_BASIC_LEDS];
	/* Print QUEUE string line exchange. */
	char comString[PRINTF_BUF_SZ];
	/* Operating mode enumerations */
	int operatingMode;
	int operatingModePrev;
	/* Selected testing address and pattern details */
	bool sf3_start_at_zero;
	uint32_t sf3_addr_start_val;// current starting address for multiple address of testing
	int sf3_test_pattern_selected;
	uint8_t sf3_pattern_start_val;
	uint8_t sf3_pattern_incr_val;
	uint8_t sf3_pattern_track_val;
	bool sf3_test_pass;
	bool sf3_test_done;
	uint32_t sf3_err_count_val;
	/* GPIO reading values at this point in the execution */
	u32 switchesRead;
	u32 buttonsRead;
	/* Timer count T for delay interval of the real-time task */
	uint32_t cnt_t;
	uint32_t cnt_t_freerun;
	/* Iteration count I for counting subsectors and pages. */
	u32 sf3_i_val;
	u32 sf3_address_of_cmd;
	/* Transmission buffers */
	u8 WriteBuffer[SF3_PAGE_SIZE + SF3_WRITE_EXTRA_BYTES];
	u8 ReadBuffer[SF3_PAGE_SIZE + SF3_READ_MIN_EXTRA_BYTES];
} t_experiment_data;

t_experiment_data experiData; // Global as that the object is always in scope, including interrupt handler.
PmodSF3 sf3Device;

/*------------------ Private Module Functions Prototypes ----*/
static void Experiment_InitData(t_experiment_data* expData);
static void Experiment_SetLedUpdate(t_experiment_data* expData,
		uint8_t silk, uint8_t red, uint8_t green, uint8_t blue);
static void Experiment_SendLedUpdate(t_experiment_data* expData, uint8_t silk);
static void Experiment_updateLedsDisplayMode(t_experiment_data* expData);
static void Experiment_updateLedsStatuses(t_experiment_data* expData);
static void Experiment_updateClsDisplayAndTerminal(t_experiment_data* expData);
static void Experiment_readUserInputs(t_experiment_data* expData);
static void Experiment_operateFSM(t_experiment_data* expData);
static void Experiment_iterationTimer(t_experiment_data* expData);

/*------------------ Global Module Functions ----------------*/
/*-----------------------------------------------------------*/
void Experiment_prvSf3Task( void *pvParameters )
{
	const TickType_t x10millisecond = pdMS_TO_TICKS( DELAY_1_SECOND / 100 );
	//const TickType_t x05millisecond = pdMS_TO_TICKS( DELAY_1_SECOND / 200 );
	XStatus Status;

	/* Initialize the PMOD SF3 driver targeted at FreeRTOS (instead of the regular
	 * PMOD SF3 driver targeted at standalone.
	 */
	Status = SF3_begin_freertos(&(sf3Device),
			XPAR_PMODSF3_0_AXI_LITE_SPI_BASEADDR,
			XPAR_INTC_0_PMODSF3_0_VEC_ID,
			XPAR_MICROBLAZE_0_AXI_INTC_PMODSF3_0_QSPI_INTERRUPT_INTR);

	if (Status != XST_SUCCESS) {
		xil_printf("Failed to initialize Pmod SF3.\r\n");
	}

	Experiment_InitData(&experiData);

	/* Initialize the GPIO device for inputting switches 0,1,2,3 and buttons 0,1,2,3.
	 * This corresponds to the two channels set in the single AXI GPIO driver of
	 * the FPGA system block design. */
	taskENTER_CRITICAL();
	XGpio_Initialize(&(experiData.axGpio), USERIO_DEVICE_ID);
	XGpio_SelfTest(&(experiData.axGpio));
	XGpio_SetDataDirection(&(experiData.axGpio), SWTCH_SW_CHANNEL, SWTCHS_SWS_MASK);
	XGpio_SetDataDirection(&(experiData.axGpio), BTNS_SW_CHANNEL, BTNS_SWS_MASK);
	taskEXIT_CRITICAL();

	/* Initialize the four color LEDs and four basic LEDs to all PWM periods set
	 * and PWM duty cycles set to zero, causing all sixteen filaments to be turned
	 * off by outputting a holding low PWM signal.
	 */
	taskENTER_CRITICAL();
	InitAllLedsOff();
	taskEXIT_CRITICAL();

	for (;;) {
		/* Update the color LEDs based on the current operating mode. */
		Experiment_updateLedsDisplayMode(&experiData);

		/* Update the basic LEDs based on current global statuses. */
		Experiment_updateLedsStatuses(&experiData);

		/* Update the Pmod CLS display based upon current state machine state and other variables */
		Experiment_updateClsDisplayAndTerminal(&experiData);

		/* Delay for X milliseconds. */
		if ((experiData.operatingMode == ST_CMD_ERASE_START) ||
				(experiData.operatingMode == ST_CMD_PAGE_START) ||
				(experiData.operatingMode == ST_CMD_READ_START))

			vTaskDelay( x10millisecond );
		else
			vTaskDelay( x10millisecond );

		/* Read the user inputs */
		Experiment_readUserInputs(&experiData);

		/* Operate a single step of the Experiment FSM */
		Experiment_operateFSM(&experiData);

		/* State change timer, wrapping at 3 seconds. */
		Experiment_iterationTimer(&experiData);
	}
}

/*------------------ Private Module Functions ----------------*/
/*-----------------------------------------------------------*/
/* Helper function to initialize the state of the \ref t_experiment_data object
 * belonging to this module's real-time task.
 */
static void Experiment_InitData(t_experiment_data* expData) {
	for (int iSilk = 0; iSilk < 6; ++iSilk) {
		Experiment_SetLedUpdate(expData, iSilk, 0x00, 0x00, 0x00);
	}

	memset(expData->comString, 0x00, PRINTF_BUF_SZ);

	expData->operatingMode = ST_WAIT_BUTTON_DEP;
	expData->operatingModePrev = ST_WAIT_BUTTON_DEP;
	expData->sf3_start_at_zero = true;
	expData->sf3_addr_start_val = 0x00000000;
	expData->sf3_test_pattern_selected = TEST_PATTERN_NONE;
	expData->sf3_pattern_start_val = sf3_test_pattern_startval_a;
	expData->sf3_pattern_incr_val = sf3_test_pattern_incrval_a;
	expData->sf3_test_pass = false;
	expData->sf3_test_done = false;
	expData->sf3_err_count_val = 0;
	expData->switchesRead = 0x00000000;
	expData->buttonsRead = 0x00000000;
	expData->cnt_t = 0;
	expData->cnt_t_freerun = 0;
}

/* Helper function to set an updated state to one of the 8 LEDs. */
static void Experiment_SetLedUpdate(t_experiment_data* expData,
		uint8_t silk, uint8_t red, uint8_t green, uint8_t blue)
{
	if (silk < 6) {
		expData->ledUpdate[silk].ledSilk = silk;
		expData->ledUpdate[silk].rgb.paletteRed = red;
		expData->ledUpdate[silk].rgb.paletteGreen = green;
		expData->ledUpdate[silk].rgb.paletteBlue = blue;
	}
}


/* Helper function to send via queue a request for LED state update */
static void Experiment_SendLedUpdate(t_experiment_data* expData,
		uint8_t silk)
{
	if (silk < 6) {
		xQueueSend( xQueueLedConfig, &(expData->ledUpdate[silk]), 0UL);
	}
}

/* Helper function for displaying LEDs 4,5,6,7 based on event count
 * and holding the LED display for a set interval of time.
 */
static void Experiment_updateLedsStatuses(t_experiment_data* expData) {
	/* Set LED status of LED0 to track test passing and test done. */
	Experiment_SetLedUpdate(expData, 2, 0, (expData->sf3_test_pass ? 100 : 0), 0);
	Experiment_SetLedUpdate(expData, 3, 0, (expData->sf3_test_done ? 100 : 0), 0);
	Experiment_SetLedUpdate(expData, 4, 0, 0, 0);
	Experiment_SetLedUpdate(expData, 5, 0, 0, 0);

	for (int iSilk = 2; iSilk < 6; ++iSilk) {
		Experiment_SendLedUpdate(expData, iSilk);
	}
}

/* Helper function for displaying Color LEDs based on Operating Mode state machine value. */
static void Experiment_updateLedsDisplayMode(t_experiment_data* expData)
{
	switch (expData->operatingMode) {
	case ST_WAIT_BUTTON_REL: /* no break */ case ST_SET_PATTERN: /* no break */ case ST_SET_START_ADDR: /* no break */ case ST_SET_START_WAIT:
		Experiment_SetLedUpdate(expData, 0,
				0,
				(expData->sf3_test_pattern_selected == TEST_PATTERN_A) ? 0xFF : 0,
				(expData->sf3_test_pattern_selected == TEST_PATTERN_C) ? 0xFF : 0);
		Experiment_SetLedUpdate(expData, 1,
				0,
				(expData->sf3_test_pattern_selected == TEST_PATTERN_B) ? 0xFF : 0,
				(expData->sf3_test_pattern_selected == TEST_PATTERN_D) ? 0xFF : 0);
		break;

	case ST_CMD_ERASE_START:
		Experiment_SetLedUpdate(expData, 0, 0x80, 0x80, 0x80);
		Experiment_SetLedUpdate(expData, 1, 0, 0, 0);
		break;

	case ST_CMD_ERASE_DONE:
		Experiment_SetLedUpdate(expData, 0, 0x70, 0x10, 0x00);
		Experiment_SetLedUpdate(expData, 1, 0, 0, 0);
		break;

	case ST_CMD_PAGE_START:
		Experiment_SetLedUpdate(expData, 0, 0, 0, 0);
		Experiment_SetLedUpdate(expData, 1, 0x80, 0x80, 0x80);
		break;

	case ST_CMD_PAGE_DONE:
		Experiment_SetLedUpdate(expData, 0, 0, 0, 0);
		Experiment_SetLedUpdate(expData, 1, 0x70, 0x10, 0x00);
		break;

	case ST_CMD_READ_START:
		Experiment_SetLedUpdate(expData, 0, 0, 0x80, 0x80);
		Experiment_SetLedUpdate(expData, 1, 0, 0, 0);
		break;

	case ST_CMD_READ_DONE:
		Experiment_SetLedUpdate(expData, 0, 0x70, 0x10, 0x00);
		Experiment_SetLedUpdate(expData, 1, 0, 0, 0);
		break;

	case ST_DISPLAY_FINAL:
		Experiment_SetLedUpdate(expData, 0, 0, 0, 0);
		Experiment_SetLedUpdate(expData, 1, 0, 0x80, 0x80);
		break;

	case ST_WAIT_BUTTON_DEP:
		/* no break */
	default: /* OPERATING_MODE_NONE */
		/* LED pattern to indicate running operating mode: waiting for button depress. */
		Experiment_SetLedUpdate(expData, 0, 0xFF, 0, 0);
		Experiment_SetLedUpdate(expData, 1, 0xFF, 0, 0);
		break;
	}

	for (int iSilk = 0; iSilk < 2; ++iSilk) {
		Experiment_SendLedUpdate(expData, iSilk);
	}
}

/* Helper function to generate the first text line for updating Pmod CLS. */
static void Experiment_generateTextLine1(t_experiment_data* expData, t_cls_lines* clsUpdate)
{
	static char cls_txt_ascii_pattern_1char = '*';

	/* Select the character to display to indicate test pattern on Pmod CLS. */
	switch (expData->sf3_test_pattern_selected) {
	case TEST_PATTERN_A:
		cls_txt_ascii_pattern_1char = 'A';
		break;
	case TEST_PATTERN_B:
		cls_txt_ascii_pattern_1char = 'B';
		break;
	case TEST_PATTERN_C:
		cls_txt_ascii_pattern_1char = 'C';
		break;
	case TEST_PATTERN_D:
		cls_txt_ascii_pattern_1char = 'D';
		break;
	default:
		cls_txt_ascii_pattern_1char = '*';
		break;
	}

	/* Generate the string of Line 1 for updating the Pmod CLS */
	snprintf(clsUpdate->line1, sizeof(clsUpdate->line1),
			"SF3 P%c h%08lx", cls_txt_ascii_pattern_1char,
			expData->sf3_addr_start_val);
}

/* Helper function to generate the second text line for updating Pmod CLS. */
static void Experiment_generateTextLine2(t_experiment_data* expData, t_cls_lines* clsUpdate)
{
	char cls_txt_ascii_sf3mode_3char[4] = "***";

	/* Select the three-character value to display to indicate
	 * simplified operating mode on the Pmod CLS as part of
	 * Line 2.
	 */
	switch (expData->operatingMode) {
	case ST_WAIT_BUTTON_REL: /* no break */ case ST_SET_PATTERN: /* no break */
	case ST_SET_START_ADDR: /* no break */ case ST_SET_START_WAIT:
		strcpy(cls_txt_ascii_sf3mode_3char, "GO ");
		break;

	case ST_CMD_ERASE_START: /* no break */ case ST_CMD_ERASE_DONE:
		strcpy(cls_txt_ascii_sf3mode_3char, "ERS");
		break;

	case ST_CMD_PAGE_START: /* no break */	case ST_CMD_PAGE_DONE:
		strcpy(cls_txt_ascii_sf3mode_3char, "PRO");
		break;

	case ST_CMD_READ_START: /* no break */ case ST_CMD_READ_DONE:
		strcpy(cls_txt_ascii_sf3mode_3char, "TST");
		break;

	case ST_DISPLAY_FINAL:
		strcpy(cls_txt_ascii_sf3mode_3char, "END");
		break;

	case ST_WAIT_BUTTON_DEP: /* no break */
	default:
		strcpy(cls_txt_ascii_sf3mode_3char, "GO ");
		break;
	}

	/* Generate the string of Line 2 for updating the Pmod CLS */
	snprintf(clsUpdate->line2, sizeof(clsUpdate->line2),
			"%s ERR %08ld", cls_txt_ascii_sf3mode_3char,
			expData->sf3_err_count_val);
}

/* Helper function for displaying SF3 state machine progress on Pmod CLS */
static void Experiment_updateClsDisplayAndTerminal(t_experiment_data* expData) {
	static t_cls_lines clsUpdate;
	static char comString[PRINTF_BUF_SZ] = "";

	/* Only refresh display at approximately 5 Hz */
	if (expData->cnt_t_freerun % (cnt_t_max / 15) != 0) {
		return;
	}

	Experiment_generateTextLine1(expData, &clsUpdate);
	Experiment_generateTextLine2(expData, &clsUpdate);

	snprintf(comString, sizeof(comString), "%s %s", clsUpdate.line1, clsUpdate.line2);

	/* Update the display to two lines of custom text to indicate
	 * SF3 Testing Progress
	 */
	xQueueSend(xQueueClsDispl, &clsUpdate, 0UL);

	/* Update the Terminal to display an additional text line with the same information as the Pmod CLS. */
	xQueueSend(xQueuePrint, comString, 0UL);
}

/* Helper function to read user inputs at this time. */
static void Experiment_readUserInputs(t_experiment_data* expData) {
	expData->switchesRead = XGpio_DiscreteRead(&(expData->axGpio), SWTCH_SW_CHANNEL);
	expData->buttonsRead = XGpio_DiscreteRead(&(expData->axGpio), BTNS_SW_CHANNEL);
}

/* Main FSM function to operate the modes of the experiment. */
static void Experiment_operateFSM(t_experiment_data* expData) {
	u8* WriteBufferPtr;
	u8* ReadBufferPtr;

	XStatus Status = 0;

	switch(expData->operatingMode) {
	case ST_WAIT_BUTTON_DEP:
		if (expData->sf3_addr_start_val < last_starting_byte_addr) {
			expData->sf3_test_done = false;

			if ((expData->buttonsRead == BTN0_MASK) || (expData->switchesRead == SWTCH0_MASK)) {
				expData->operatingMode = ST_WAIT_BUTTON_REL;
				expData->sf3_test_pattern_selected = TEST_PATTERN_A;

			} else if ((expData->buttonsRead == BTN1_MASK) || (expData->switchesRead == SWTCH1_MASK)) {
				expData->operatingMode = ST_WAIT_BUTTON_REL;
				expData->sf3_test_pattern_selected = TEST_PATTERN_B;

			} else if ((expData->buttonsRead == BTN2_MASK) || (expData->switchesRead == SWTCH2_MASK)) {
				expData->operatingMode = ST_WAIT_BUTTON_REL;
				expData->sf3_test_pattern_selected = TEST_PATTERN_C;

			} else if ((expData->buttonsRead == BTN3_MASK) || (expData->switchesRead == SWTCH3_MASK)) {
				expData->operatingMode = ST_WAIT_BUTTON_REL;
				expData->sf3_test_pattern_selected = TEST_PATTERN_D;
			}
		} else {
			expData->sf3_test_done = true;
		}
		break;

	case ST_WAIT_BUTTON_REL:
		if (expData->buttonsRead == 0x00000000) {
			expData->operatingMode = ST_SET_PATTERN;
		} else {
			/* stay in state */
		}
		break;

	case ST_SET_PATTERN:
		switch (expData->sf3_test_pattern_selected) {
		case TEST_PATTERN_A:
			expData->sf3_pattern_start_val = sf3_test_pattern_startval_a;
			expData->sf3_pattern_incr_val = sf3_test_pattern_incrval_a;
			break;
		case TEST_PATTERN_B:
			expData->sf3_pattern_start_val = sf3_test_pattern_startval_b;
			expData->sf3_pattern_incr_val = sf3_test_pattern_incrval_b;
			break;
		case TEST_PATTERN_C:
			expData->sf3_pattern_start_val = sf3_test_pattern_startval_c;
			expData->sf3_pattern_incr_val = sf3_test_pattern_incrval_c;
			break;
		case TEST_PATTERN_D:
			expData->sf3_pattern_start_val = sf3_test_pattern_startval_d;
			expData->sf3_pattern_incr_val = sf3_test_pattern_incrval_d;
			break;
		}
		expData->operatingMode = ST_SET_START_ADDR;
		break;

	case ST_SET_START_ADDR:
		if (expData->sf3_start_at_zero) {
			expData->sf3_addr_start_val = 0x00000000;
			expData->sf3_test_done = false;
			expData->operatingMode = ST_SET_START_WAIT;
		} else if (expData->sf3_addr_start_val < last_starting_byte_addr) {
			expData->sf3_addr_start_val += per_iteration_byte_count;
			expData->sf3_test_done = false;
			expData->operatingMode = ST_SET_START_WAIT;
		} else {
			expData->sf3_test_done = true;
			expData->operatingMode = ST_WAIT_BUTTON_DEP;
		}

		expData->sf3_start_at_zero = false;
		expData->sf3_i_val = 0;
		break;

	case ST_SET_START_WAIT:
		if (expData->cnt_t == cnt_t_max / 2) {
			expData->operatingMode = ST_CMD_ERASE_START;
		}
		break;

	case ST_CMD_ERASE_START:
		expData->sf3_address_of_cmd = expData->sf3_addr_start_val + (expData->sf3_i_val * sf3_subsector_addr_incr);

		Status = SF3_FlashWriteEnable(&sf3Device);

		if (Status != XST_SUCCESS) {
			snprintf(expData->comString, PRINTF_BUF_SZ, "WEN Fail");
			xQueueSend(xQueuePrint, expData->comString, 0UL);
		}

		Status = SF3_SectorErase(&sf3Device, expData->sf3_address_of_cmd);

		if (Status != XST_SUCCESS) {
			snprintf(expData->comString, PRINTF_BUF_SZ, "Ers Fail %08lx", expData->sf3_address_of_cmd);
			xQueueSend(xQueuePrint, expData->comString, 0UL);
		}

		expData->sf3_i_val += 1;
		if (expData->sf3_i_val < experi_subsector_cnt_per_iter)
			expData->operatingMode = ST_CMD_ERASE_START;
		else
			expData->operatingMode = ST_CMD_ERASE_DONE;
		break;

	case ST_CMD_ERASE_DONE:
		expData->sf3_pattern_track_val = expData->sf3_pattern_start_val;
		expData->sf3_i_val = 0;

		if (expData->cnt_t >= cnt_t_max - 1) {
			expData->operatingMode = ST_CMD_PAGE_START;
		} else {
			expData->operatingMode = ST_CMD_ERASE_DONE;
		}
		break;

	case ST_CMD_PAGE_START:
		for (int j = 0; j < 32; ++j) {
			expData->sf3_address_of_cmd = expData->sf3_addr_start_val + (expData->sf3_i_val * sf3_page_addr_incr);

			Status = SF3_FlashWriteEnable(&sf3Device);

			if (Status != XST_SUCCESS) {
				snprintf(expData->comString, PRINTF_BUF_SZ, "WEN Fail");
				xQueueSend(xQueuePrint, expData->comString, 0UL);
			}

			for(int iByte = 0; iByte < SF3_PAGE_SIZE; ++iByte)
			{
				expData->WriteBuffer[iByte + SF3_WRITE_EXTRA_BYTES] = expData->sf3_pattern_track_val;
				expData->sf3_pattern_track_val += expData->sf3_pattern_incr_val;
			}
			WriteBufferPtr = &(expData->WriteBuffer[0]);
			Status = SF3_FlashWrite(&sf3Device, expData->sf3_address_of_cmd, SF3_PAGE_SIZE, SF3_COMMAND_PAGE_PROGRAM, &(WriteBufferPtr));

			if (Status != XST_SUCCESS) {
				snprintf(expData->comString, PRINTF_BUF_SZ, "PRO Fail %08lx", expData->sf3_address_of_cmd);
				xQueueSend(xQueuePrint, expData->comString, 0UL);
			}

			expData->sf3_pattern_track_val = expData->sf3_pattern_start_val;
			expData->sf3_i_val += 1;
			if (expData->sf3_i_val < experi_page_cnt_per_iter)
				expData->operatingMode = ST_CMD_PAGE_START;
			else
				expData->operatingMode = ST_CMD_PAGE_DONE;
		}
		break;

	case ST_CMD_PAGE_DONE:
		expData->sf3_pattern_track_val = expData->sf3_pattern_start_val;
		expData->sf3_i_val = 0;

		if (expData->cnt_t >= cnt_t_max - 1) {
			expData->operatingMode = ST_CMD_READ_START;
		} else {
			expData->operatingMode = ST_CMD_PAGE_DONE;
		}
		break;

	case ST_CMD_READ_START:
		for (int j = 0; j < 32; ++j) {
			expData->sf3_address_of_cmd = expData->sf3_addr_start_val + (expData->sf3_i_val * sf3_page_addr_incr);

			for(int iByte = 0; iByte < SF3_PAGE_SIZE + SF3_READ_MIN_EXTRA_BYTES; ++iByte)
			{
				expData->ReadBuffer[iByte + SF3_READ_MIN_EXTRA_BYTES] = 0x00;
			}
			ReadBufferPtr = &(expData->ReadBuffer[0]);

			Status = SF3_FlashRead(&(sf3Device), expData->sf3_address_of_cmd, SF3_PAGE_SIZE, SF3_COMMAND_RANDOM_READ, &(ReadBufferPtr));

			if (Status != XST_SUCCESS) {
				snprintf(expData->comString, PRINTF_BUF_SZ, "RD  Fail %08lx", expData->sf3_address_of_cmd);
				xQueueSend(xQueuePrint, expData->comString, 0UL);
			}

			expData->sf3_pattern_track_val = expData->sf3_pattern_start_val;
			for(int iByte = 0; iByte < SF3_PAGE_SIZE; ++iByte)
			{
				expData->sf3_err_count_val += (expData->ReadBuffer[iByte + SF3_READ_MIN_EXTRA_BYTES] == expData->sf3_pattern_track_val) ? 0 : 1;
				expData->sf3_pattern_track_val += expData->sf3_pattern_incr_val;
			}

			expData->sf3_pattern_track_val = expData->sf3_pattern_start_val;
			expData->sf3_i_val += 1;
			if (expData->sf3_i_val < experi_page_cnt_per_iter)
				expData->operatingMode = ST_CMD_READ_START;
			else
				expData->operatingMode = ST_CMD_READ_DONE;
		}
		break;

	case ST_CMD_READ_DONE:
		expData->sf3_pattern_track_val = expData->sf3_pattern_start_val;
		expData->sf3_i_val = 0;

		if (expData->cnt_t >= cnt_t_max - 1) {
			expData->operatingMode = ST_DISPLAY_FINAL;
		} else {
			expData->operatingMode = ST_CMD_READ_DONE;
		}
		break;

	case ST_DISPLAY_FINAL:
		expData->sf3_test_pass = (expData->sf3_err_count_val) ? false : true;
		if (expData->cnt_t == cnt_t_max - 1) {
			expData->operatingMode = ST_WAIT_BUTTON_DEP;
		}
		break;

	default: /* If state unknown or NONE, then transition to waiting for button/switch depress. */
		expData->operatingMode = ST_WAIT_BUTTON_DEP;
		break;
	}
}

/* Timer function similar to VHDL/Verilog FSM Timer strategy #1. */
static void Experiment_iterationTimer(t_experiment_data* expData) {
	/* Reset timer on 15 iterations or change in operating mode */
	if (expData->operatingMode != expData->operatingModePrev) {
		expData->cnt_t = 0;
	} else {
		expData->cnt_t = (expData->cnt_t + 1) % cnt_t_max; /* 3 seconds of counting on 10 ms timer */
	}

	expData->cnt_t_freerun = (expData->cnt_t_freerun + 1) % cnt_t_max; /* 3 seconds of counting on 10 ms timer */

	/* Track operating mode history (only one step back) */
	expData->operatingModePrev = expData->operatingMode;
}
