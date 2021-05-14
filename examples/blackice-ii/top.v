/*
 *  NERV -- Naive Educational RISC-V Processor
 *
 *  Copyright (C) 2020  Miodrag Milanovic <miodrag@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

module top(
	input CLK,
	output LED1,
	output LED2,
	output LED3,
	output LED4,
	output LED5,
	output LED6,
	output LED7
);

// Create reset signal 16 clocks long
reg reset = 1'b1;
reg [3:0] reset_cnt = 0;
always @(posedge CLK)
begin
	reset <= (reset_cnt != 15);
	reset_cnt <= reset_cnt + (reset_cnt != 15);
end

// Map 8 LEDs on PMOD11/12
wire [31:0] leds;
assign { LED8, LED7, LED6, LED5, LED4, LED3, LED2, LED1 } = { leds[7:0] };

nervsoc soc (
	.clock(CLK),
	.reset(reset),
	.leds(leds)
);

endmodule
