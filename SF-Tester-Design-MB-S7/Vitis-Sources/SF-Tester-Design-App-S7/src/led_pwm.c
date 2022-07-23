/**-----------------------------------------------------------------------------
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
 * @file led_pwm.c
 *
 * @brief
 * LED control API for controlling FPGA-connected LEDs of the Arty S7
 * FPGA prototyping board by Digilent Inc by interfacing them with the
 * Digilent PWM_2.0 IP block.
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

#include "led_pwm.h"
#include "PWM.h"
#include "xparameters.h"

/**-----------------------------------------------------------------------------
 * @brief
 * The PWM_0 block is assigned a base AXI address and a PWM period calculated
 * at 10 millisecond duration.
 */
static const t_color_pwm_constants c_color_pwms[N_COLOR_PWMS] = {
	{XPAR_PWM_0_PWM_AXI_BASEADDR, PWM_PERIOD_TEN_MILLISECOND}
};

/**-----------------------------------------------------------------------------
 * @brief
 * The PWM_0 block is assigned a base AXI address and a PWM duty cycle maximum
 * calculated at 7 millisecond duration, for each color filament of the four
 * color LEDs of the Arty A7 board.
 */
static const t_color_led_constants c_color_leds[N_COLOR_LEDS] = {
		{XPAR_PWM_0_PWM_AXI_BASEADDR, 0, PWM_DUTY_CYCLE_SEVEN_MILLISECOND, 'r', 0},
		{XPAR_PWM_0_PWM_AXI_BASEADDR, 1, PWM_DUTY_CYCLE_SEVEN_MILLISECOND, 'g', 0},
		{XPAR_PWM_0_PWM_AXI_BASEADDR, 2, PWM_DUTY_CYCLE_SEVEN_MILLISECOND, 'b', 0},
		{XPAR_PWM_0_PWM_AXI_BASEADDR, 3, PWM_DUTY_CYCLE_SEVEN_MILLISECOND, 'r', 1},
		{XPAR_PWM_0_PWM_AXI_BASEADDR, 4, PWM_DUTY_CYCLE_SEVEN_MILLISECOND, 'g', 1},
		{XPAR_PWM_0_PWM_AXI_BASEADDR, 5, PWM_DUTY_CYCLE_SEVEN_MILLISECOND, 'b', 1}
};

/**-----------------------------------------------------------------------------
 * @brief
 * The PWM_1 block is assigned a base AXI address and a PWM period calculated
 * at 10 millisecond duration.
 */
static const t_basic_pwm_constants c_basic_pwms[N_BASIC_PWMS] = {
	{XPAR_PWM_1_PWM_AXI_BASEADDR, PWM_PERIOD_TEN_MILLISECOND}
};

/**-----------------------------------------------------------------------------
 * @brief
 * The PWM_1 block is assigned a base AXI address and a PWM duty cycle maximum
 * calculated at 9 millisecond duration, for each basic filament of the four
 * basic LEDs of the Arty A7 board.
 */
static const t_basic_led_constants c_basic_leds[N_BASIC_LEDS] = {
		{XPAR_PWM_1_PWM_AXI_BASEADDR, 0, PWM_DUTY_CYCLE_NINE_MILLISECOND, 2},
		{XPAR_PWM_1_PWM_AXI_BASEADDR, 1, PWM_DUTY_CYCLE_NINE_MILLISECOND, 3},
		{XPAR_PWM_1_PWM_AXI_BASEADDR, 2, PWM_DUTY_CYCLE_NINE_MILLISECOND, 4},
		{XPAR_PWM_1_PWM_AXI_BASEADDR, 3, PWM_DUTY_CYCLE_NINE_MILLISECOND, 5}
};

/**-----------------------------------------------------------------------------
 * @brief
 * Initializes the Color LED filaments to an OFF state such that the PWM duty
 * cycle is set to zero clock cycles and the PWM period is set to the default
 * constant value. This presets the color LED filaments to OFF.
 */
void InitColorLedsOff(void) {
	int i = 0;

	for(i = 0; i < N_COLOR_PWMS; ++i) {
		PWM_Set_Period(c_color_pwms[i].baseAddr, c_color_pwms[i].pwmPeriod);
	}
	for(i = 0; i < N_COLOR_LEDS; ++i) {
		PWM_Set_Duty(c_color_leds[i].baseAddr, 0, c_color_leds[i].pwmIndex);
	}
	for(i = 0; i < N_COLOR_PWMS; ++i) {
		PWM_Enable(c_color_pwms[i].baseAddr);
	}
}

/**-----------------------------------------------------------------------------
 * @brief
 * Initializes the Basic LED filaments to an OFF state such that the PWM period
 * is set to its default constant value and the PWM duty cycle is set to zero
 * clock cycles. This presets the basic LED filaments to OFF.
 */
void InitBasicLedsOff(void) {
	int i = 0;

	for(i = 0; i < N_BASIC_PWMS; ++i) {
		PWM_Set_Period(c_basic_pwms[i].baseAddr, c_basic_pwms[i].pwmPeriod);
	}
	for(i = 0; i < N_BASIC_LEDS; ++i) {
		PWM_Set_Duty(c_basic_leds[i].baseAddr, 0, c_basic_leds[i].pwmIndex);
	}
	for(i = 0; i < N_BASIC_PWMS; ++i) {
		PWM_Enable(c_basic_pwms[i].baseAddr);
	}
}

/**-----------------------------------------------------------------------------
 * @brief
 * Turn OFF the color LEDs with initial preset, and then turn off the Basic LEDs
 * with initial preset.
 */
void InitAllLedsOff(void) {
	InitColorLedsOff();
	InitBasicLedsOff();
}

/**-----------------------------------------------------------------------------
 * @brief
 * Set a color LED filament to a percentage of the constant maximum duty cycle
 * strength, which is a major fraction of the PWM period value.
 *
 * @param ledSilk the board silkscreen index of the LED component
 * @param color the RGB filament within the color LED expressed as 'r', 'g', 'b'
 * @param percentFixPt a fixed-point integer of the percentage of strength
 *                     expressed as increments of 0.1%. The value 100 is 10.0%.
 *
 * @return zero for success at finding the filament to adjust, non-zero
 *         otherwise
 */
int SetColorLedPercent(const u8 ledSilk, const char color, const u32 percentFixPt) {
	int i = 0;
	u32 dutyClocks = 0;
	int ret = 1; // Failure

	for (i = 0; (i < N_COLOR_LEDS) && ret; ++i) {
		if (c_color_leds[i].silkLedIndex == ledSilk) {
			if (c_color_leds[i].filamentColor == color) {
				dutyClocks = percentFixPt * c_color_leds[i].maxDutyCycle / 1000;
				PWM_Set_Duty(c_color_leds[i].baseAddr, dutyClocks, c_color_leds[i].pwmIndex);
				ret = 0; // Success
			}
		}
	}

	return ret;
}

/**-----------------------------------------------------------------------------
 * @brief
 * Set a basic LED filament to a percentage of the constant maximum duty cycle
 * strength, which is a major fraction of the PWM period value.
 *
 * @param ledSilk the board silkscreen index of the LED component
 * @param percentFixPt a fixed-point integer of the percentage of strength
 *                     expressed as increments of 0.1%. The value 100 is 10.0%.
 *
 * @return zero for success at finding the filament to adjust, non-zero
 *         otherwise
 */
int SetBasicLedPercent(const u8 ledSilk, const u32 percentFixPt) {
	int i = 0;
	u32 dutyClocks = 0;
	int ret = 1; // Failure

	for (i = 0; (i < N_BASIC_LEDS) && ret; ++i) {
		if (c_basic_leds[i].silkLedIndex == ledSilk) {
			dutyClocks = percentFixPt * c_basic_leds[i].maxDutyCycle / 1000;
			PWM_Set_Duty(c_basic_leds[i].baseAddr, dutyClocks, c_basic_leds[i].pwmIndex);
			ret = 0; // Success
		}
	}

	return ret;
}

/*
int WaitLedPeriodTimerTick(const u32 elapsed, const u32 waitLoad, u32* waitTimer) {
	int ret = 0;

	if (*waitTimer > elapsed) {
		*waitTimer -= elapsed;
		ret = 1;
	} else {
		*waitTimer = waitLoad - (elapsed - *waitTimer);
		ret = 0;
	}

	return ret;
}
*/

/**-----------------------------------------------------------------------------
 * @brief
 * Set a color LED three RGB filaments to a percentage of duty cycle strength
 * based upon a 24-bit color value, 8-bits for each filament.
 *
 * @param ledSilk the board silkscreen index of the LED component
 * @param palette a pointer to the palette structure to input as three 8-bit
 *        color strength values, one for each RGB filament.
 *
 * @return zero for success at finding the filaments to adjust, non-zero
 *         otherwise
 */
int SetRgbPaletteLed(const u8 ledSilk, const t_rgb_led_palette* palette) {
	int ret0 = 0;
	int ret1 = 0;
	int ret2 = 0;

	ret0 = SetColorLedPercent(ledSilk, 'r', palette->paletteRed * 1000 / 255);
	ret1 = SetColorLedPercent(ledSilk, 'g', palette->paletteGreen * 1000 / 255);
	ret2 = SetColorLedPercent(ledSilk, 'b', palette->paletteBlue * 1000 / 255);

	return (ret0 || ret1 || ret2) ? 1 : 0;
}
