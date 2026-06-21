/*
 * Copyright (c) 2024 Uri Shaked
 * Modified for SLS Rocket Orbit and Moon
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused outputs assigned to 0
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in};

  // 12-bit counter for animation phases
  reg [11:0] counter;

  // 18-bit signed registers for the Minsky Circle oscillator 
  reg signed [17:0] osc_x;
  reg signed [17:0] osc_y;
  reg vsync_prev;

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );

  // ==========================================
  // BULLETPROOF MINSKY OSCILLATOR MATH
  // ==========================================
  
  wire signed [17:0] y_shifted = { {5{osc_y[17]}}, osc_y[17:5] };
  wire signed [17:0] next_x    = osc_x - y_shifted;
  
  wire signed [17:0] next_x_shifted = { {5{next_x[17]}}, next_x[17:5] };
  wire signed [17:0] next_y    = osc_y + next_x_shifted;

  wire [9:0] rocket_x = 10'd320 + osc_x[17:8];
  wire [9:0] rocket_y = 10'd240 + osc_y[17:8];

  // ==========================================
  // SLS ROCKET GEOMETRY
  // ==========================================
  
  wire [9:0] dy = pix_y - rocket_y;
  wire [9:0] dx = (pix_x > rocket_x) ? (pix_x - rocket_x) : (rocket_x - pix_x);

  // Orion Spacecraft & Stage Adapter
  wire is_orion = (dy < 10'd25) && (dx < (dy[9:1] + 1)); 

  // Core Stage
  wire is_core = (dy >= 10'd25) && (dy < 10'd130) && (dx <= 10'd8);

  // Twin Solid Rocket Boosters (SRBs)
  wire is_srb_nose = (dy >= 10'd35) && (dy < 10'd45) && (dx >= 10'd9) && (dx <= 10'd16) && ((dx - 10'd9) <= (dy - 10'd35));
  wire is_srb_body = (dy >= 10'd45) && (dy < 10'd130) && (dx >= 10'd9) && (dx <= 10'd16);
  wire is_srb = is_srb_nose | is_srb_body;

  // Flames (Core Stage vs SRBs)
  wire [9:0] core_flame_len = counter[3] ? 10'd20 : 10'd10;
  wire is_core_flame = (dy >= 10'd130) && (dy < (10'd130 + core_flame_len)) && (dx <= 10'd6);

  wire [9:0] srb_flame_len = counter[2] ? 10'd35 : 10'd25;
  wire [9:0] flame_dy_srb = dy - 10'd130;
  wire is_srb_flame = (dy >= 10'd130) && (dy < (10'd130 + srb_flame_len)) && (dx >= 10'd9) && (dx <= (10'd16 - flame_dy_srb[9:3]));

  wire is_flame = is_core_flame | is_srb_flame;

  // ==========================================
  // MOON & STAR GEOMETRY
  // ==========================================

  wire near_moon = (pix_x > 10'd250) && (pix_x < 10'd390) && (pix_y > 10'd170) && (pix_y < 10'd310);
  wire [6:0] moon_dx = (pix_x > 10'd320) ? pix_x - 10'd320 : 10'd320 - pix_x;
  wire [6:0] moon_dy = (pix_y > 10'd240) ? pix_y - 10'd240 : 10'd240 - pix_y;
  wire [6:0] cut_dx  = (pix_x > 10'd335) ? pix_x - 10'd335 : 10'd335 - pix_x;

  wire is_moon_base = near_moon && ((moon_dx * moon_dx + moon_dy * moon_dy) < 14'd1600);
  wire is_cut       = near_moon && ((cut_dx * cut_dx + moon_dy * moon_dy) < 14'd1600);
  wire is_moon      = is_moon_base && ~is_cut;

  wire is_star = (pix_x[4:0] == 5'b01001) && (pix_y[5:0] == 6'b101101) && (pix_x[8] ^ pix_y[7]);

  // ==========================================
  // COLOR MAPPING
  // ==========================================

  wire is_white_part = is_orion | is_srb;
  wire is_orange_part = is_core;

  wire [1:0] r_out = is_moon        ? 2'b11 : // Yellow moon
                     is_white_part  ? 2'b11 : // White SLS parts
                     is_orange_part ? 2'b11 : // Rust core stage
                     is_flame       ? 2'b11 : // Orange/Red flame
                     is_star        ? 2'b01 : 2'b00;

  // For the core stage, giving it max Red and low Green creates an Orange/Rust color
  wire [1:0] g_out = is_moon        ? 2'b11 : // Yellow moon
                     is_white_part  ? 2'b11 : // White SLS parts
                     is_orange_part ? 2'b01 : // Rust core stage
                     is_flame       ? (counter[2] ? 2'b10 : 2'b01) : // Flickering flame
                     is_star        ? 2'b01 : 2'b00;

  wire [1:0] b_out = is_moon        ? 2'b00 : // Yellow moon
                     is_white_part  ? 2'b11 : // White SLS parts
                     is_orange_part ? 2'b00 : // Rust core stage
                     is_flame       ? 2'b00 : // Orange/Red flame
                     is_star        ? 2'b10 : 2'b00;

  assign R = video_active ? r_out : 2'b00;
  assign G = video_active ? g_out : 2'b00;
  assign B = video_active ? b_out : 2'b00;
  
  // ==========================================
  // SYNCHRONOUS PHYSICS UPDATE
  // ==========================================
  
  always @(posedge clk) begin
    if (~rst_n) begin
      counter <= 0;
      osc_x <= 18'sd30720;
      osc_y <= 18'sd0;
      vsync_prev <= 0;
    end else begin
      vsync_prev <= vsync;
      if (vsync && ~vsync_prev) begin
        counter <= counter + 1;
        osc_x <= next_x;
        osc_y <= next_y;
      end
    end
  end

endmodule