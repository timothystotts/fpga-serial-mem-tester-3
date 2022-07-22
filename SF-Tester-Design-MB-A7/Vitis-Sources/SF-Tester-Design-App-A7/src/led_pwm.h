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
 * @file led_pwm.h
 *
 * @brief
 * LED control API for controlling FPGA-connected LEDs of the Arty A7
 * FPGA prototyping board by Digilent Inc.
 *
 * @author
 * Timothy Stotts (timothystotts08@gmail.com)
 *
 * @copyright
 * (c) 2019 Copyright Timothy Stotts
 *
 * This program is free software; distributed under the terms of the MIT
 * License.
------------------------------------------------------------------------------*/

#ifndef SRC_LED_PWM_H_
#define SRC_LED_PWM_H_

#include "xil_types.h"

#define PWM_PERIOD_TEN_MILLISECOND ((u32)500000)
#define PWM_DUTY_CYCLE_NINE_MILLISECOND ((u32)500000 * 9 / 10)
#define PWM_DUTY_CYCLE_EIGHT_MILLISECOND ((u32)500000 * 8 / 10)
#define PWM_DUTY_CYCLE_SEVEN_MILLISECOND ((u32)500000 * 7 / 10)
#define PWM_DUTY_CYCLE_FIVE_MILLISECOND ((u32)500000 * 5 / 10)

typedef struct COLOR_PWM_TAG {
	u32 baseAddr;
	u32 pwmPeriod;
} t_color_pwm_constants;

typedef struct COLOR_LED_TAG {
	u32 baseAddr; /* The base address of the PWM module that controls this filament. */
	u32 pwmIndex;
	u32 maxDutyCycle;
	char filamentColor;
	u8 silkLedIndex;
} t_color_led_constants;

typedef struct RGB_LED_TAG {
	u8 paletteRed;
	u8 paletteGreen;
	u8 paletteBlue;
} t_rgb_led_palette;

typedef struct RGB_LED_SILK_TAG {
	t_rgb_led_palette rgb;
	u8 ledSilk;
} t_rgb_led_palette_silk;

typedef t_color_pwm_constants t_basic_pwm_constants;

typedef struct BASIC_LED_TAG {
	u32 baseAddr;
	u32 pwmIndex;
	u32 maxDutyCycle;
	u8 silkLedIndex;
} t_basic_led_constants;

void InitAllLedsOff(void);
int SetColorLedPercent(const u8 ledSilk, const char color, const u32 percentFixPt);
int SetBasicLedPercent(const u8 ledSilk, const u32 percentFixPt);
int WaitLedPeriodTimerTick(const u32 elapsed, const u32 waitLoad, u32* waitTimer);
int SetRgbPaletteLed(const u8 ledSilk, const t_rgb_led_palette* palette);

#endif /* SRC_LED_PWM_H_ */
