;===============================================================================
; Project:      PIC12F1571 / PIC12F1572 4-Channel ADC to 200 kbps Serial Bridge
; Author:       Ivo Andonov
; Version:      1.0.0
; Date:         November 2026
; License:      MIT
;
; Description:  Samples 2 fast analog channels @ 4 kHz (AN0, AN1) and 2 slow
;               channels @ 15.625 Hz (AN2, AN4), streaming 10-bit little-endian
;               frames over a bit-banged 200 kbps (8N1) UART on RA5.
;
; Target MCU:   PIC12F1571 or PIC12F1572 @ 32 MHz (8 MHz HFINTOSC + 4x PLL)
; Instruction:  8 MIPS (125 ns/cycle) | Timer0 ISR Tick: 40 cycles (5.00 us)
; Toolchain:    MPASM (mpasmx)
;
; Pinout:
;   RA0 (AN0) - Fast ADC Channel 1 (4 kHz)
;   RA1 (AN1) - Fast ADC Channel 2 (4 kHz)
;   RA2 (AN2) - Slow ADC Channel 1 (15.625 Hz)
;   RA3       - MCLR (Active-Low Reset, 10k pull-up)
;   RA4 (AN3) - Slow ADC Channel 2 (15.625 Hz)
;   RA5       - Software UART TX (200,000 bps, 8N1, Idle HIGH)
;
; Frame Format (1,030 bytes @ 15.625 Hz):
;   [0xFF, 0xFE] + [Slow1 (2B)] + [Slow2 (2B)] + [256 x (Fast1 (2B), Fast2 (2B))]
;
; CRITICAL ARCHITECTURE NOTES (DO NOT MODIFY LIGHTLY):
;   1. Main loop MUST remain a 2-cycle `bra $` to lock ISR entry latency at
;      4 cycles (zero bit-banging jitter).
;   2. Hardware shadow registers preserve W (-40+3), BSR (Bank 1), FSR0 (TMR0),
;      and FSR1 (PORTA) across interrupts. Do not alter these in main!
;   3. All GPRs in Bank 1 must stay within 0xA0-0xBF for PIC12F1571 compatibility.
;===============================================================================

#include p12f1572.inc

  radix dec
	errorlevel -302
	errorlevel -224
 	errorlevel -207
 __CONFIG _CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_ON & _BOREN_ON & _CLKOUTEN_OFF
 __CONFIG _CONFIG2, _WRT_ALL & _PLLEN_ON & _STVREN_ON & _BORV_HI & _LPBOREN_ON & _LVP_OFF

	cblock 0xA0
		serState:   1 ;
		serByte:    1 ; current byte value being sent
		serPin:     1 ;
		serRdPos:   1 ;
		serWrPos:   1 ;
		adcState:   1 ;
		adcCnt:     1 ;
		samples:    1 ;
		adcReg:     1 ;
	endc
 
	#define BUFBASE 0x20
	cblock BUFBASE
		serBuf:  16 ;
	endc
	
 	cblock 0x78
	endc
	
RES_VECT:  org    0x0000            ; processor reset vector
	GOTO    START                   ; go to beginning of program

ISR:       org    0x0004           ; interrupt vector location
	addwf INDF0, f
  bcf INTCON, TMR0IF
	
	movf serPin, w
	movwf INDF1
	
	movf adcReg, w
	btfss STATUS, Z
		movwf ADCON0
	clrf adcReg
	
	decf adcCnt, f

	bsf serPin, 5
	movf serState, w
	brw
ser_states:
ser_start:
ser_send_start_bit:
	bcf serPin, 5
	movlw ser_send_bit_0 - ser_states
	bra ser_done
ser_send_bit_0:
	btfss serByte, 0
		bcf serPin, 5
	movlw ser_send_bit_1 - ser_states
	bra ser_done
ser_send_bit_1:
	btfss serByte, 1
		bcf serPin, 5
	movlw ser_send_bit_2 - ser_states
	bra ser_done
ser_send_bit_2:
	btfss serByte, 2
		bcf serPin, 5
	movlw ser_send_bit_3 - ser_states
	bra ser_done
ser_send_bit_3:
	btfss serByte, 3
		bcf serPin, 5
	movlw ser_send_bit_4 - ser_states
	bra ser_done
ser_send_bit_4:
	btfss serByte, 4
		bcf serPin, 5
	movlw ser_send_bit_5 - ser_states
	bra ser_done
ser_send_bit_5:
	btfss serByte, 5
		bcf serPin, 5
	movlw ser_send_bit_6 - ser_states
	bra ser_done
ser_send_bit_6:
	btfss serByte, 6
		bcf serPin, 5
	movlw ser_send_bit_7 - ser_states
	bra ser_done
ser_send_bit_7:
	btfss serByte, 7
		bcf serPin, 5
	movlw ser_send_stop_bit - ser_states
	bra ser_done
ser_send_stop_bit:
	;fall through
ser_idle:
	movf serRdPos, w
	xorwf serWrPos, w
	btfss STATUS, Z
	  bra ser_next_byte
	bra ser_x
ser_next_byte:
	movf serRdPos, w
	movwf FSR0L
	movf INDF0, w
	movwf serByte

	incf serRdPos, w
	andlw 0x0F
	iorlw BUFBASE
	movwf serRdPos
	movlw ser_start - ser_states
ser_done:
	movwf serState
ser_x:
	
adc:
	movf adcState, w
	brw
adc_states:
	
; <editor-fold defaultstate="collapsed" desc="ADC1">
adc_1:
	movlw adc_1_start_conv - adc_states
	bra adc_x
adc_1_start_conv:
	movlw b'00000011'
	movwf adcReg

	movlw adc_1_wait_conv_1 - adc_states
	bra adc_x
adc_1_wait_conv_1:
	movlw adc_1_wait_conv_2 - adc_states
	bra adc_x
adc_1_wait_conv_2:
	movlw adc_1_store_result - adc_states
	bra adc_x
adc_1_store_result:
	movf serWrPos, w
	movwf FSR0L
	movf ADRESL, w
	movwi FSR0++
	movf ADRESH, w
	movwi FSR0++
	
	movf FSR0L, w
	andlw 0x0F
	iorlw BUFBASE
	movwf serWrPos
	
	movlw adc_1_next - adc_states
	movwf adcState
	retfie
adc_1_next:
	movlw b'00000101'
	movwf ADCON0
	
	movlw adc_2 - adc_states
	movwf adcState
	retfie
;</editor-fold>

; <editor-fold defaultstate="collapsed" desc="ADC2">
adc_2:
	movlw adc_2_start_conv - adc_states
	bra adc_x
adc_2_start_conv:
	movlw b'00000111'
	movwf adcReg

	movlw adc_2_wait_conv_1 - adc_states
	bra adc_x
adc_2_wait_conv_1:
	movlw adc_2_wait_conv_2 - adc_states
	bra adc_x
adc_2_wait_conv_2:
	movlw adc_2_store_result - adc_states
	bra adc_x
adc_2_store_result:
	movf serWrPos, w
	movwf FSR0L
	movf ADRESL, w
	movwi FSR0++
	movf ADRESH, w
	movwi FSR0++
	
	movf FSR0L, w
	andlw 0x0F
	iorlw BUFBASE
	movwf serWrPos
	
	movlw adc_2_next - adc_states
	movwf adcState
	retfie
adc_2_next:
	decf samples, f
	btfsc STATUS, Z
		bra go_sample_3
	movlw b'00000001'
	movwf ADCON0
	
	movlw adc_idle - adc_states
	movwf adcState
	retfie
go_sample_3:
	movlw b'00001001'
	movwf ADCON0
	movlw adc_3 - adc_states
	movwf adcState
	retfie
;</editor-fold>

; <editor-fold defaultstate="collapsed" desc="ADC3">
adc_3:
	movf serWrPos, w
	movwf FSR0L
	movlw 0xff
	movwi FSR0++
	movlw 0xfe
	movwi FSR0++
	
	movf FSR0L, w
	andlw 0x0F
	iorlw BUFBASE
	movwf serWrPos

	movlw adc_3_start_conv - adc_states
	bra adc_x
adc_3_start_conv:
	movlw b'00001011'
	movwf adcReg

	movlw adc_3_wait_conv_1 - adc_states
	bra adc_x
adc_3_wait_conv_1:
	movlw adc_3_wait_conv_2 - adc_states
	bra adc_x
adc_3_wait_conv_2:
	movlw adc_3_store_result - adc_states
	bra adc_x
adc_3_store_result:
	movf serWrPos, w
	movwf FSR0L
	movf ADRESL, w
	movwi FSR0++
	movf ADRESH, w
	movwi FSR0++
	
	movf FSR0L, w
	andlw 0x0F
	iorlw BUFBASE
	movwf serWrPos
	
	movlw adc_3_next - adc_states
	movwf adcState
	retfie
adc_3_next:
	movlw b'00001101'
	movwf ADCON0
	
	movlw adc_4 - adc_states
	movwf adcState
	retfie
;</editor-fold>

; <editor-fold defaultstate="collapsed" desc="ADC4">
adc_4:
	movlw adc_4_start_conv - adc_states
	bra adc_x
adc_4_start_conv:
	movlw b'00001111'
	movwf adcReg

	movlw adc_4_wait_conv_1 - adc_states
	bra adc_x
adc_4_wait_conv_1:
	movlw adc_4_wait_conv_2 - adc_states
	bra adc_x
adc_4_wait_conv_2:
	movlw adc_4_store_result - adc_states
	bra adc_x
adc_4_store_result:
	movf serWrPos, w
	movwf FSR0L
	movf ADRESL, w
	movwi FSR0++
	movf ADRESH, w
	movwi FSR0++
	
	movf FSR0L, w
	andlw 0x0F
	iorlw BUFBASE
	movwf serWrPos
	
	movlw adc_4_next - adc_states
	movwf adcState
	retfie
adc_4_next:
	movlw b'00000001'
	movwf ADCON0
	
	movlw adc_idle - adc_states
	movwf adcState
	retfie
;</editor-fold>

adc_idle:
	movf adcCnt, f
	btfss STATUS, Z
		bra adc_x
	
	movlw 50
	movwf adcCnt
	
	movlw adc_1 - adc_states
adc_x:
	movwf adcState

	retfie
	
START:			
	banksel OSCCON
	movlw b'11110000'
	movwf OSCCON
	movlw 0xff
	movwf serPin
	movwf LATA
	movlw b'11011111'
	TRIS 5
	banksel ANSELA
	movlw b'00010111'
	movwf ANSELA
	banksel ADCON0
	movlw b'00000001'
	movwf ADCON0
	clrf adcReg
	movlw b'10100000'
	movwf ADCON1
	movlw b'00000000'
	movwf ADCON2

	clrf FSR0H
	clrf FSR1H

	movlw PORTA
	movwf FSR1L

	movlw TMR0
	movwf FSR0L

	movlw 0xff & ~(1 << TMR0CS)
	OPTION

	banksel ADCON0
	movlw ser_idle - ser_states
	movwf serState
	
	movlw serBuf
	movwf serWrPos
	movwf serRdPos
	
	movlw adc_idle - adc_states
	movwf adcState
	
	movlw -40 + 3
	bsf INTCON, TMR0IE
	bsf INTCON, GIE
loop:
	bra loop
	
	
	END