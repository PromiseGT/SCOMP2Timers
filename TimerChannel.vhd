library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TimerChannel is
    port (
        SYS_CLK   : in  std_logic;
        RESETN    : in  std_logic;
        TICK_1MS  : in  std_logic;
        CS        : in  std_logic;
        IO_READ   : in  std_logic;
        IO_WRITE  : in  std_logic;
        REG_ADDR  : in  std_logic_vector(2 downto 0);
        WRITE_DATA: in  std_logic_vector(15 downto 0);
        READ_DATA : out std_logic_vector(15 downto 0)
    );
end TimerChannel;

architecture rtl of TimerChannel is
    signal ctrl : std_logic_vector(3 downto 0) := (others => '0');
    signal count_ms : integer range 0 to 999 := 0;
    signal count_s  : unsigned(15 downto 0) := (others => '0');
    signal start_ms : integer range 0 to 999 := 0;
    signal start_s  : unsigned(15 downto 0) := (others => '0');
    signal lap_ms   : integer range 0 to 999 := 0;
    signal lap_s    : unsigned(15 downto 0) := (others => '0');
    signal alarm_ms : integer range 0 to 999 := 0;
    signal alarm_s  : unsigned(15 downto 0) := (others => '0');
    signal pending_count_ms : integer range 0 to 999 := 0;
    signal pending_alarm_ms : integer range 0 to 999 := 0;
    signal snapshot_ms : integer range 0 to 999 := 0;
    signal snapshot_s  : unsigned(15 downto 0) := (others => '0');
    signal flags       : std_logic_vector(2 downto 0) := (others => '0');
    signal wr_level, rd_ms_level : std_logic;
    signal wr_prev, rd_ms_prev   : std_logic := '0';
    signal wr_pulse, rd_ms_pulse : std_logic;
    signal ms_read_value        : std_logic_vector(15 downto 0);
begin
    wr_level    <= CS and IO_WRITE;
    rd_ms_level <= CS and IO_READ when REG_ADDR = "001" else '0';
    wr_pulse    <= wr_level and (not wr_prev);
    rd_ms_pulse <= rd_ms_level and (not rd_ms_prev);
    ms_read_value <= std_logic_vector(to_unsigned(count_ms, 16))
                     when rd_ms_pulse = '1' else
                     std_logic_vector(to_unsigned(snapshot_ms, 16));
    with REG_ADDR select
        READ_DATA <= ("000000000000" & ctrl)                  when "000", -- CTRL
                     ms_read_value                           when "001", -- COUNT ms
                     std_logic_vector(snapshot_s)           when "010", -- COUNT s
                     std_logic_vector(to_unsigned(lap_ms,16)) when "011", -- LAP ms
                     std_logic_vector(lap_s)                when "100", -- LAP s
                     std_logic_vector(to_unsigned(alarm_ms,16)) when "101", -- ALARM ms
                     std_logic_vector(alarm_s)              when "110", -- ALARM s
                     ("0000000000000" & flags)              when others; -- FLAGS
    process (SYS_CLK, RESETN)
        variable v_ms       : integer range 0 to 999;
        variable v_s        : unsigned(15 downto 0);
        variable v_start_ms : integer range 0 to 999;
        variable v_start_s  : unsigned(15 downto 0);
        variable v_ctrl     : std_logic_vector(3 downto 0);
        variable v_flags    : std_logic_vector(2 downto 0);
        variable advanced   : boolean;
        variable hit_zero   : boolean;
        variable raw_ms     : integer range 0 to 65535;
    begin
        if RESETN = '0' then
            ctrl             <= (others => '0');
            count_ms         <= 0;
            count_s          <= (others => '0');
            start_ms         <= 0;
            start_s          <= (others => '0');
            lap_ms           <= 0;
            lap_s            <= (others => '0');
            alarm_ms         <= 0;
            alarm_s          <= (others => '0');
            pending_count_ms <= 0;
            pending_alarm_ms <= 0;
            snapshot_ms      <= 0;
            snapshot_s       <= (others => '0');
            flags            <= (others => '0');
            wr_prev          <= '0';
            rd_ms_prev       <= '0';
        elsif rising_edge(SYS_CLK) then
            wr_prev    <= wr_level;
            rd_ms_prev <= rd_ms_level;
            v_ms       := count_ms;
            v_s        := count_s;
            v_start_ms := start_ms;
            v_start_s  := start_s;
            v_ctrl     := ctrl;
            v_flags    := flags;
            advanced   := false;
            hit_zero   := false;
            if TICK_1MS = '1' and ctrl(0) = '1' then
                if ctrl(1) = '0' then
                    if v_ms = 999 then
                        v_ms := 0;
                        if v_s = to_unsigned(65535,16) then
                            v_s := (others => '0');
                            v_flags(2) := '1';
                        else
                            v_s := v_s + 1;
                        end if;
                    else
                        v_ms := v_ms + 1;
                    end if;
                    advanced := true;
                else
                    if v_s = to_unsigned(0,16) and v_ms = 0 then
                        v_ctrl(0) := '0';
                    else
                        if v_ms = 0 then
                            v_ms := 999;
                            v_s  := v_s - 1;
                        else
                            v_ms := v_ms - 1;
                        end if;
                        advanced := true;
                        if v_s = to_unsigned(0,16) and v_ms = 0 then
                            hit_zero := true;
                            v_flags(0) := '1';
                        end if;
                    end if;
                end if;
                if advanced and ctrl(3) = '1' and
                   v_ms = alarm_ms and v_s = alarm_s then
                    v_flags(1) := '1';
                end if;

                if hit_zero then
                    if ctrl(2) = '1' and
                       (v_start_ms /= 0 or v_start_s /= to_unsigned(0,16)) then
                        v_ms := v_start_ms;
                        v_s  := v_start_s;
                    else
                        v_ctrl(0) := '0';
                    end if;
                end if;
            end if;
            if wr_pulse = '1' then
                case REG_ADDR is
                    when "000" => 
                        v_ctrl := WRITE_DATA(3 downto 0);
                        if WRITE_DATA(4) = '1' then
                            v_ms := v_start_ms;
                            v_s  := v_start_s;
                        end if;
                    when "001" => 
                        raw_ms := to_integer(unsigned(WRITE_DATA));
                        if raw_ms > 999 then
                            pending_count_ms <= 999;
                        else
                            pending_count_ms <= raw_ms;
                        end if;
                    when "010" => -- COUNT s commits the pair + start value
                        v_ms       := pending_count_ms;
                        v_s        := unsigned(WRITE_DATA);
                        v_start_ms := pending_count_ms;
                        v_start_s  := unsigned(WRITE_DATA);
                    when "011" => -- LAP ms captures both parts
                        lap_ms <= v_ms;
                        lap_s  <= v_s;
                    when "100" => -- unused
                        null;
                    when "101" => -- ALARM ms holding register
                        raw_ms := to_integer(unsigned(WRITE_DATA));
                        if raw_ms > 999 then
                            pending_alarm_ms <= 999;
                        else
                            pending_alarm_ms <= raw_ms;
                        end if;
                    when "110" => -- ALARM s commits the pair
                        alarm_ms <= pending_alarm_ms;
                        alarm_s  <= unsigned(WRITE_DATA);
                    when others => -- FLAGS: write-one-to-clear
                        v_flags := v_flags and (not WRITE_DATA(2 downto 0));
                end case;
            end if;

            -- A countdown cannot start or remain running at zero.
            if v_ctrl(0) = '1' and v_ctrl(1) = '1' and
               v_ms = 0 and v_s = to_unsigned(0,16) then
                v_ctrl(0) := '0';
            end if;

            -- A COUNT-ms read snapshots both halves at the same edge.
            if rd_ms_pulse = '1' then
                snapshot_ms <= count_ms;
                snapshot_s  <= count_s;
            end if;

            count_ms <= v_ms;
            count_s  <= v_s;
            start_ms <= v_start_ms;
            start_s  <= v_start_s;
            ctrl     <= v_ctrl;
            flags    <= v_flags;
        end if;
    end process;
end rtl;
