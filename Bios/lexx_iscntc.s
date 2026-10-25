.segment "CODE"
; ----------------------------------------------------------------------------
; KBD ISCNTC
; Simple implementation that calls `get_key` and checks for Ctrl+C (ASCII $03).
; Note: this consumes a pending key from the input stream when present.
; Returns: A = #$01 if Ctrl+C detected, A = #$00 otherwise
; Preserves processor status and X/Y via stack pushes/pops.
; ----------------------------------------------------------------------------
ISCNTC:

    jsr get_key       ; get_key returns ASCII in A (or 0 if none)
    cmp #$03          ; Ctrl-C ASCII
    beq not_ctrl_c

    rts
not_ctrl_c:
