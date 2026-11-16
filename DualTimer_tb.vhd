-- DualTimer_tb.vhd: standalone simulation (not a synthesizable design).
-- A smaller CLOCK_HZ is used here to speed up simulation.
-- IO_READ / IO_WRITE follow the uploaded SCOMP bus interface.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DualTimer_tb is
end DualTimer_tb;

architecture sim of DualTimer_tb is
    signal sys_clk   : std_logic := '0';
    signal resetn    : std_logic := '0';
    signal io_read   : std_logic := '0';
    signal io_write  : std_logic := '0';
    signal io_addr   : std_logic_vector(10 downto 0) := (others => '0');
    signal io_data   : std_logic_vector(15 downto 0);
    signal cpu_data  : std_logic_vector(15 downto 0) := (others => 'Z');

    -- Watch these two signals in the simulator.
    -- TEST_COMPLETE = 1 means the test has finished.
    -- TEST_PASSED = 1 means every check passed.
    signal TEST_COMPLETE : std_logic := '0';
    signal TEST_PASSED   : std_logic := '0';
begin
    sys_clk <= not sys_clk after 5 ns;
    io_data <= cpu_data;

    DUT : entity work.DualTimer(rtl)
        generic map (CLOCK_HZ => 100000)
        port map (
            SYS_CLK => sys_clk, RESETN => resetn,
            IO_READ => io_read, IO_WRITE => io_write,
            IO_ADDR => io_addr, IO_DATA => io_data
        );

    process
        procedure write_reg(constant a : natural; constant val : natural) is
        begin
            wait until falling_edge(sys_clk);
            io_addr <= std_logic_vector(to_unsigned(a,11));
            cpu_data <= std_logic_vector(to_unsigned(val,16));
            io_write <= '1';
            wait until falling_edge(sys_clk);
            io_write <= '0';
            cpu_data <= (others => 'Z');
            wait until rising_edge(sys_clk);
        end procedure;

        procedure read_reg(constant a : natural;
                           variable value : out std_logic_vector(15 downto 0)) is
        begin
            wait until falling_edge(sys_clk);
            io_addr <= std_logic_vector(to_unsigned(a,11));
            cpu_data <= (others => 'Z');
            io_write <= '0';
            io_read <= '1';
            wait until rising_edge(sys_clk);
            wait for 1 ns;
            value := io_data;
            wait until falling_edge(sys_clk);
            io_read <= '0';
            wait until rising_edge(sys_clk);
        end procedure;

        variable got : std_logic_vector(15 downto 0);
        variable paused_ms : integer;
        variable failures  : integer := 0;
    begin
        wait for 75 ns;
        wait until falling_edge(sys_clk);
        resetn <= '1';

        -- Timer 0 stopwatch, stop after about 2.5 simulated ms ticks.
        write_reg(16#70#, 16#11#); -- RUN + RESET
        wait for 2500 ns;
        write_reg(16#70#, 0);      -- pause
        read_reg(16#71#, got);     -- ms first
        paused_ms := to_integer(unsigned(got));
        if not (paused_ms >= 2 and paused_ms <= 3) then
            failures := failures + 1;
        end if;
        read_reg(16#72#, got);
        if not (got = x"0000") then
            failures := failures + 1;
        end if;

        -- Lap capture: writes ignore the data value.
        write_reg(16#73#, 0);
        read_reg(16#73#, got);
        if not (to_integer(unsigned(got)) = paused_ms) then
            failures := failures + 1;
        end if;

        -- Timer 1: 3 ms countdown should set DONE and auto-clear RUN.
        write_reg(16#79#, 3);     -- COUNT ms staged
        write_reg(16#7A#, 0);     -- COUNT seconds, commit 0.003
        write_reg(16#7F#, 1);     -- clear DONE
        write_reg(16#78#, 3);     -- RUN + DIR
        wait for 5000 ns;
        read_reg(16#7F#, got);
        if not (got(0) = '1') then
            failures := failures + 1;
        end if;
        read_reg(16#78#, got);
        if not (got(0) = '0') then
            failures := failures + 1;
        end if;
        write_reg(16#7F#, 1);
        read_reg(16#7F#, got);
        if not (got(0) = '0') then
            failures := failures + 1;
        end if;

        -- Timer 0 alarm at 0.005 seconds.
        write_reg(16#75#, 5);     -- ALARM ms staged
        write_reg(16#76#, 0);     -- ALARM s commits
        write_reg(16#77#, 2);     -- clear ALARM
        write_reg(16#70#, 16#19#); -- RUN + ALARM_EN + RESET
        wait for 7000 ns;
        read_reg(16#77#, got);
        if not (got(1) = '1') then
            failures := failures + 1;
        end if;

        -- Timer 1: periodic 2 ms auto-reload; DONE remains sticky and RUN stays on.
        write_reg(16#79#, 2);
        write_reg(16#7A#, 0);
        write_reg(16#7F#, 1);
        write_reg(16#78#, 7);  -- RUN + DIR + RELOAD
        wait for 5500 ns;
        read_reg(16#7F#, got);
        if not (got(0) = '1') then
            failures := failures + 1;
        end if;
        read_reg(16#78#, got);
        if not (got(0) = '1') then
            failures := failures + 1;
        end if;
        write_reg(16#78#, 0);

        -- Timer 0: overflowing the maximum time wraps to zero and sets flag.
        write_reg(16#70#, 0);        -- pause
        write_reg(16#71#, 999);      -- ms stage
        write_reg(16#72#, 65535);    -- commit 65535.999
        write_reg(16#77#, 4);        -- clear OVERFLOW
        write_reg(16#70#, 1);        -- count up
        wait for 2500 ns;
        read_reg(16#77#, got);
        if not (got(2) = '1') then
            failures := failures + 1;
        end if;
        write_reg(16#70#, 0);
        read_reg(16#71#, got);       -- ms read makes snapshot
        if not (unsigned(got) < to_unsigned(1000, 16)) then
            failures := failures + 1;
        end if;
        read_reg(16#72#, got);       -- corresponding seconds
        if not (got = x"0000") then
            failures := failures + 1;
        end if;

        -- Check TEST_COMPLETE and TEST_PASSED in the simulator waveform.
        TEST_COMPLETE <= '1';
        if failures = 0 then
            TEST_PASSED <= '1';
        end if;
        wait;
    end process;
end sim;
