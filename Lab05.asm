/**************************************************************************
 *	    File: Lab05.asm
 *  Lab Name: Pardon the Interruption...
 *    Author: Dr. Greg Nordstrom
 *   Created: 02/19/2021
 * Processor: ATmega128A (on the ReadyAVR board)
 *
 * Modified by: Jose De Los Santos
 * Modified on: September 22, 2026
 *
 * This program changes the BOOT LED light's frequency between 1Hz to 15Hz 
 * by pressing the UP/DOWN buttons. This physical input triggers an 
 *(I)interrupt (S)ervice (R)outine in the program that alters the MAIN 
 *program loops that either increase or decrease the LED blink rate. The 
 *blink rate is displayed in a 4-bit binary pattern on LEDs 3:0 from 
 *PORTC.3(MSB) to PORTC.1(LSB). The LED bit pattern is only adjusted
 *once the button is released. 
 *
 *The joystick switches are physically connected to PORTB pins but they
 *themselves cannot generate interrupts. By jumping wires between PB1 and
 *PB3 to PD1 and PD3,respectively, interrupts can be generated via joystick.
 *
 *The first couple of lines include definitions and the vectors used for
 *the interrupts. The code begins by setting up which ports control what.
 * The BOOT LED was set by PA.7, PB.3:0 were the output LEDs, and PD.3 and
 *PD.1 were set up to enable interrupts. 
 *The MAIN program a series of loops
 *that control the blink rate of the BOOT LED. The program on its own was
 set to run at 1Hz. When either ISR was triggered, the program immediately
 *saves its return address and jumps to the vector address in the vector
 *table.
 *The ISRs would begin by saving the current R16 loop count and the SREG
 *flags. The next step was to compare the current BlinkFreq value to either
 *Max or Min depending on the ISR triggered. A branch instruction will then
 *either branch to exit the ISR via RETI or INC/DEC the value of BlinkFreq.
 *The value will then be displayed on the PC.3:0 LEDs and will display the
 *resulting bit pattern there.
 *************************************************************************/
 .def BlinkFreq		   = R20; holds the current blink rate (1-15Hz)
 .equ BlinkFreqMin	   = 1
 .equ BlinkFreqMax	   = 15
 .equ InitialBlinkFreq = BlinkFreqMin

 .equ INT1_addr = 0x0004	; vector location for external interrupt 1
 .equ INT3_addr = 0x0008	; vector location for external interrupt 3
 /*********
 * Interrupt Jump Table
 *********/
.org 0x0000                 ; next instruction address is 0x0000
                            ; (the location of the reset vector)
rjmp main					; allow reset to run this program

.org INT1_addr				; external interrupt 1
RJMP int1_isr				; jump to ext. interrupt 1

.org INT3_addr				; external interrupt 3
RJMP int3_isr				; jump to ext. interrupt 3

/**********
* Main code
**********/
.org INT_VECTORS_SIZE; places MAIN after vector table (0x0046)
main:                       ; jump here on reset
    ldi R16, HIGH(RAMEND)   ; initialize stack (default RAMEND = 0x10FF)
    out SPH, R16
    ldi R16, low(RAMEND)
    out SPL, R16

	/* Additional Setup before Main Loop */

    LDI  R16,(1<<DDA7)		; Set the mask to make PIN_A7 an output
    OUT  DDRA,R16			; Sets PA7 as output for BOOT LED
    SBI	 PORTA, PORTA7		; PA7 HIGH, BOOT LED active low

	LDI  R16, 0x00			; Sets the mask to make all DDRB as inputs
	OUT	 DDRB, R16			; Sets PB3 and PB1 as inputs for the joystick
	SBI	 PORTB, PORTB3		; Enable pull-up on PB3
	SBI  PORTB, PORTB1		; Enable pull-up on PB1

	LDI	 R16, (1<<DDC3|1<<DDC2|1<<DDC1|1<<DDC0); mask with PC3:0
	OUT  DDRC, R16			; Sets PINS 3:0 as outputs for blink rate LEDs

	LDI  R16, 0x00			; Sets the mask to make all DDRD as inputs
	OUT	 DDRD, R16			; PD3 and PD1 are inputs to trigger ISRs
	
	LDI	 R16, (1<<ISC31|1<<ISC30|1<<ISC11|1<<ISC10) ; Sets EICRA to trigger on rising edge
	STS	 EICRA, R16			; EICRA is in Ext.I/O, needed to use STS instead of OUT

	LDI	 R16, (1<<INT3|1<<INT1); Sets mask to enable INT3(UP) and INT1(DOWN)
	OUT	 EIMSK, R16			; Loads EIMSK register with bits to enable INT3 and INT1

	LDI	 BlinkFreq, InitialBlinkFreq; start BlinkFreq at 1Hz
	LDI R16, 0x0F			; Mask for 4 LED bits**
	EOR R16, BlinkFreq		; Invert bits 3:0 (active low)**
	OUT	PORTC, R16			; Sends initial LED value of 1 to 3:0

	SEI						; Enable Global Interrupts, raises I bit in SREG

mainLoop:
    CBI  PORTA, PORTA7      ; turn BOOT LED on (active low) by clearing PORTA.7

    ; kill some time
    ldi R16, 16             ; R16 is outer loop counter
	SUB R16, BlinkFreq		; R16 = R16 - BlinkFreq
outer_loop1:
    ldi R24, low(0xFFFF)    ; load low and high parts of R25:R24 pair with
    ldi R25, high(0xFFFF)   ; loop count by loading registers separately
    inner_loop1:
        sbiw R24, 1         ; decrement inner loop counter (R25:R24 pair)
        brne inner_loop1    ; loop back if R25:R24 isn't zero
    dec R16                 ; decrement the outer loop counter (R16)
    brne outer_loop1        ; loop back if R16 isn't zero

    sbi PORTA, PORTA7       ; turn BOOT LED off (active low) by setting PORTA.7

    ; kill some more time
    ldi R16, 16             ; R16 is outer loop counter
	SUB R16, BlinkFreq		; R16 = R16 - BlinkFreq
outer_loop2:
    ldi R24, low(0xFFFF)    ; load low and high parts of R25:R24 pair with
    ldi R25, high(0xFFFF)   ; loop count by loading registers separately
    inner_loop2:
        sbiw R24, 1         ; decrement inner loop counter (R25:R24 pair)
        brne inner_loop2    ; loop back if R25:R24 isn't zero
    dec R16                 ; decrement the outer loop counter (R16)
    brne outer_loop2        ; loop back if R16 isn't zero

    rjmp mainLoop           ; play it again, Sam...

/**********
* ISR code
**********/
;.org 0x0200				; Load the ISR code higher than main code
/**************************************************
* int3_ISR "UP" button is pressed on joystick******
* IFFF BlinkFreq(R20) is less than BlinkFreqMax(15)
* increment by 1 and update LEDs 3:0***************
**************************************************/
int3_isr:
	 PUSH R16				; Pushes current R16 loop count to stack
	 IN R16, SREG			; Loads SREG's current flags into R16
	 PUSH R16				; Pushes flag statuses to stack
	 CPI BlinkFreq, BlinkFreqMax; Compares current LED freq vs Max LED value
	 BRSH up_finished		; Branch if BFreq is equal to BFreqMax, jump
	 INC BlinkFreq			; Increase BlinkFreq by 1 if false
	 LDI R16, 0x0F	 		; mask for 4 LED bits
	 EOR R16, BlinkFreq		; invert bits 3:0 (active low)
	 OUT PORTC, R16			; Show new rate on LEDs 3:0
	 
up_finished:
	 POP R16				; Loads pre ISR SREG flags onto R16
	 OUT SREG, R16			; Loads pre ISR flags back onto SREG
	 POP R16				; Loads original loop count onto R16
	 RETI					; exits ISR and returns to MAIN

/*****************************************************
* int1_ISR "DOWN" button is pressed on joystick*******
* IFFF BlinkFreq(R20) is less than BlinkFreqMin(+1)***
* decrement by 1 and update LEDs 3:0******************
*****************************************************/
int1_isr:
	 PUSH R16				; Pushes current R16 loop count to stack
	 IN R16, SREG			; Loads SREG's current flags into R16
	 PUSH R16				; Pushes flag statuses to stack
	 CPI BlinkFreq, BlinkFreqMin+1; Compares current LED freq vs Min LED value(+1)
	 BRLO down_finished		; Branch if BFreq is less than 2, jump
	 DEC BlinkFreq			; Decrease BlinkFreq by 1 if false
	 LDI R16, 0x0F	 		; mask for 4 LED bits
	 EOR R16, BlinkFreq		; invert bits 3:0 (active low)
	 OUT PORTC, R16	; Show new rate on LEDs 3:0
	 
down_finished:
	 POP R16				; Loads pre ISR SREG flags onto R16
	 OUT SREG, R16			; Loads pre ISR flags back onto SREG
	 POP R16				; Loads original loop count onto R16
	 RETI					; exits ISR and returns to MAIN