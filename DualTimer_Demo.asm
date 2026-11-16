; SCOMP DualTimer demo: Timer 1 counts down 5.000 seconds.
; Compatible with the instructions in your uploaded SCOMP.vhd.
; After DONE, the program stays in Finished. Read AC or RAM via debug.

Start:
        LOADI 0
        OUT   &H79       ; Timer 1 count milliseconds = 0 (staged)
        LOADI 5
        OUT   &H7A       ; Load 5 seconds, commit both parts
        LOADI 1
        OUT   &H7F       ; Clear previous DONE flag
        LOADI 3
        OUT   &H78       ; RUN + DIR (count down)

Wait5:
        IN    &H7F       ; Read Timer 1 FLAGS
        AND   DoneMask   ; Only test DONE bit
        JZERO Wait5      ; Repeat until 5 seconds elapse

Finished:
        IN    &H7F       ; Flag should still be 1 (sticky)
        STORE DoneValue  ; RAM write for checking in simulation
        JUMP  Finished

DoneMask: DW 1
DoneValue: DW 0
