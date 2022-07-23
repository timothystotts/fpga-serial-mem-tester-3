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
 * @file freertos_main.c
 *
 * @brief
 * The main routine to initialize and schedule FreeRTOS Queues and Tasks to
 * operate the SF-Tester-Design-AXI project that performs an FPGA memory tester
 * of the PmodSF3.
 *
 * @author
 * Timothy Stotts (timothystotts08@gmail.com)
 *
 * @copyright
 * (c) 2020 Copyright Timothy Stotts
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
#include "xgpio.h"
/* Project includes. */
#include "intc.h"
#include "PmodCLS.h"
#include "PmodSF3.h"
#include "PWM.h"
#include "led_pwm.h"
#include "Experiment.h"

/*-----------------------------------------------------------*/

/* Task handles for controlling real-time tasks */
static TaskHandle_t xLedTask;
static TaskHandle_t xClsTask;
static TaskHandle_t xSf3Task;
static TaskHandle_t xPrintTask;

/* Queues for generating update events */
QueueHandle_t xQueuePrint = NULL;
QueueHandle_t xQueueLedConfig = NULL;
QueueHandle_t xQueueClsDispl = NULL;

/* The real-time tasks of this program. */
static void prvLedTask( void *pvParameters ); /* Update LEDs on events */
static void prvClsTask( void *pvParameters ); /* Print to PMOD CLS on events */
static void prvSf3Task( void *pvParameters ); /* Master task, operate PMOD ACL2 and generate events. */
static void prvPrintTask( void *pvParameters ); /* Print to UARTlite on events */

/*-----------------------------------------------------------*/
int main( void )
{
	/* Create a task to receive events for updating LED color palette for eight LEDs of the Arty-A7-100. */
	xTaskCreate( prvLedTask,
				 (const char*) "LC",
				 configMINIMAL_STACK_SIZE,
				 NULL,
				 tskIDLE_PRIORITY,
				 &xLedTask );

	/* Create a task to receive 16x2 text line updates to the external dot-matrix LCD of the PMOD CLS. */
	xTaskCreate( prvClsTask,
				 (const char*) "CLS",
				 configMINIMAL_STACK_SIZE,
				 NULL,
				 tskIDLE_PRIORITY,
				 &xClsTask );

	/* Create a task to read updates from the PMOD SF3, and send queue updates for LED, CLS, Printf . */
	xTaskCreate( prvSf3Task,
				 (const char*) "SF3",
				 configMINIMAL_STACK_SIZE + (2*1024),
				 NULL,
				 tskIDLE_PRIORITY + 2,
				 &xSf3Task);

	/* Create a task to receive strings to print to the UART via xil_printf(). */
	xTaskCreate( prvPrintTask,
				 ( const char * ) "PRINT",
				 configMINIMAL_STACK_SIZE,
				 NULL,
				 tskIDLE_PRIORITY + 1,
				 &xPrintTask );

	/* Create the LED configuration Queue for receiving events for LED configuration. */
	xQueueLedConfig = xQueueCreate(10, sizeof(t_rgb_led_palette_silk));

	/* Create the 16x2 dot-matrix LCD display receiving text updates queue. */
	xQueueClsDispl = xQueueCreate(4, sizeof(t_cls_lines));

	/* Create the serial console printf() queue for short strings to print to console. */
	xQueuePrint = xQueueCreate(4, PRINTF_BUF_SZ);

	/* Check the queue was created. */
	configASSERT(xQueueLedConfig);

	/* Check the queue was created. */
	configASSERT(xQueueClsDispl);

	/* Check the queue was created. */
	configASSERT(xQueuePrint);

	/* Start the tasks and timer running. */
	vTaskStartScheduler();

	/* If all is well, the scheduler will now be running, and the following line
	will never be reached.  If the following line does execute, then there was
	insufficient FreeRTOS heap memory available for the idle and/or timer tasks
	to be created.  See the memory management section on the FreeRTOS web site
	for more details. */
	for( ;; );
}

/*-----------------------------------------------------------*/
static void prvLedTask( void *pvParameters )
{
	t_rgb_led_palette_silk currLedConfig;
	InitAllLedsOff();

	for (;;)
	{
		/* Block on LED configuration queue to receive the next incoming event. */
		xQueueReceive(xQueueLedConfig, &currLedConfig, portMAX_DELAY);

		taskENTER_CRITICAL();
		if (currLedConfig.ledSilk < 2) {
			SetRgbPaletteLed(currLedConfig.ledSilk, &(currLedConfig.rgb));
		} else if (currLedConfig.ledSilk < 6) {
			SetBasicLedPercent(currLedConfig.ledSilk, currLedConfig.rgb.paletteGreen);
		}
		taskEXIT_CRITICAL();
	}
}

/*-----------------------------------------------------------*/
static void prvClsTask( void *pvParameters )
{
	static PmodCLS clsDevice;
	t_cls_lines clsLines;

	taskENTER_CRITICAL();

	/* Initialize the PMOD CLS 16x2 dot-matrix LCD display. */
	memset(&clsDevice, 0x00, sizeof(clsDevice));
	CLS_begin(&clsDevice, XPAR_PMODCLS_0_AXI_LITE_SPI_BASEADDR);

	/* Clear the display. */
	CLS_DisplayClear(&clsDevice);

	taskEXIT_CRITICAL();

	for (;;) {
		/* Block on CLS lines queue to receive the next incoming display text update. */
		xQueueReceive(xQueueClsDispl, &clsLines, portMAX_DELAY);

		taskENTER_CRITICAL();

		if ((strnlen(clsLines.line1, 16) == 0) && (strnlen(clsLines.line2, 16) == 0)) {
			/* If both lines are only null strings, then clear the display and print nothing. */
			CLS_DisplayClear(&clsDevice);
		} else {
			/* Otherwise, clear the display and print the two lines of text. */
			CLS_DisplayClear(&clsDevice);
			CLS_WriteStringAtPos(&clsDevice, 0, 0, clsLines.line1);
			CLS_WriteStringAtPos(&clsDevice, 1, 0, clsLines.line2);
		}

		taskEXIT_CRITICAL();
	}
}

/*-----------------------------------------------------------*/
static void prvSf3Task( void *pvParameters )
{
	Experiment_prvSf3Task(pvParameters);
}

/*-----------------------------------------------------------*/
static void prvPrintTask( void *pvParameters )
{
	char Recdstring[PRINTF_BUF_SZ] = "";

	for( ;; )
	{
		/* Block to wait for data arriving on the queue. */
		xQueueReceive( 	xQueuePrint,				/* The queue being read. */
						Recdstring,	/* Data is read into this address. */
						portMAX_DELAY );	/* Wait without a timeout for data. */

		/* Print the received data. */
		xil_printf( "%s\r\n", Recdstring );
	}
}

