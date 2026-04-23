
module final_chip(clk, rst_n, uart_rx, uart_tx, test_in, test_out, 
     tck, tms, trst_n, tdi, tdo, dft_sen, dft_sdi, dft_sdo, 
     dft_sdi_1, dft_sdo_1, dft_sdi_2, dft_sdo_2, 
     VDD_IO, VSS_IO, VDD, VSS);
  input clk, rst_n, uart_rx, test_in, tck, tms, trst_n, tdi, dft_sen,
       dft_sdi, dft_sdi_1, dft_sdi_2;
  output uart_tx, test_out, tdo, dft_sdo, dft_sdo_1, dft_sdo_2;
  inout VDD, VDD_IO;
  inout VSS, VSS_IO;

  wire wire_clk, wire_rst_n, wire_uart_rx, wire_test_in, wire_tck, wire_tms, wire_trst_n, wire_tdi, wire_dft_sen,
       wire_dft_sdi, wire_dft_sdi_1, wire_dft_sdi_2;
  wire wire_uart_tx, wire_test_out, wire_tdo, wire_dft_sdo, wire_dft_sdo_1, wire_dft_sdo_2;
  rk4_projectile_top u_rk4_projectile_top(wire_clk, wire_rst_n, wire_uart_rx, wire_uart_tx, wire_test_in,
                                            wire_test_out, wire_tck, wire_tms, wire_trst_n, wire_tdi, wire_tdo,
                                              wire_dft_sen, wire_dft_sdi, wire_dft_sdo, wire_dft_sdi_1,
                                               wire_dft_sdo_1, wire_dft_sdi_2, wire_dft_sdo_2);
  
  // IO and Power Pins
  PVDD2CDG Pad_VDD_IO_top(VDD_IO);
  PVSS2CDG Pad_VSS_IO_top(VSS_IO);
  PVDD1CDG Pad_VDD_top(.VDD(VDD));
  PVSS3CDG Pad_VSS_top(.VSS(VSS));
  
  PVDD2CDG Pad_VDD_IO_bottom(VDD_IO);
  PVSS2CDG Pad_VSS_IO_bottom(VSS_IO);
  PVDD1CDG Pad_VDD_bottom(.VDD(VDD));
  PVSS3CDG Pad_VSS_bottom(.VSS(VSS));
  
  PVDD2CDG Pad_VDD_IO_left(VDD_IO);
  PVSS2CDG Pad_VSS_IO_left(VSS_IO);
  PVDD1CDG Pad_VDD_left(.VDD(VDD));
  PVSS3CDG Pad_VSS_left(.VSS(VSS));
  
  PVDD2CDG Pad_VDD_IO_right(VDD_IO);
  PVSS2CDG Pad_VSS_IO_right(VSS_IO);
  PVDD1CDG Pad_VDD_right(.VDD(VDD));
  PVSS3CDG Pad_VSS_right(.VSS(VSS));

  // inputs
  PDDW1216CDG Pad_IO_clk_0(     .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(clk),       .C(wire_clk),       .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_rst_n_0(   .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(rst_n),     .C(wire_rst_n),     .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_uart_rx_0( .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(uart_rx),   .C(wire_uart_rx),   .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_test_in_0( .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(test_in),   .C(wire_test_in),   .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_tck_0(     .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(tck),       .C(wire_tck),       .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_tms_0(     .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(tms),       .C(wire_tms),       .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_trst_n_0(  .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(trst_n),    .C(wire_trst_n),    .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_tdi_0(     .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(tdi),       .C(wire_tdi),       .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_dft_sen_0( .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(dft_sen),   .C(wire_dft_sen),   .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_dft_sdi_0( .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(dft_sdi),   .C(wire_dft_sdi),   .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_dft_sdi_1( .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(dft_sdi_1), .C(wire_dft_sdi_1), .PE(1'b0), .IE(1'b1) );
  PDDW1216CDG Pad_IO_dft_sdi_2( .I(1'b0), .DS(1'b0), .OEN(1'b1), .PAD(dft_sdi_2), .C(wire_dft_sdi_2), .PE(1'b0), .IE(1'b1) );

  // outputs
  PDDW1216CDG Pad_IO_uart_tx_0( .I(wire_uart_tx),   .DS(1'b0), .OEN(1'b0), .PAD(uart_tx),   .C(),  .PE(1'b0), .IE(1'b0) );
  PDDW1216CDG Pad_IO_test_out_0(.I(wire_test_out),  .DS(1'b0), .OEN(1'b0), .PAD(test_out),  .C(),  .PE(1'b0), .IE(1'b0) );
  PDDW1216CDG Pad_IO_tdo_0(     .I(wire_tdo),       .DS(1'b0), .OEN(1'b0), .PAD(tdo),       .C(),  .PE(1'b0), .IE(1'b0) );
  PDDW1216CDG Pad_IO_dft_sdo_0( .I(wire_dft_sdo),   .DS(1'b0), .OEN(1'b0), .PAD(dft_sdo),   .C(),  .PE(1'b0), .IE(1'b0) );
  PDDW1216CDG Pad_IO_dft_sdo_1( .I(wire_dft_sdo_1), .DS(1'b0), .OEN(1'b0), .PAD(dft_sdo_1), .C(),  .PE(1'b0), .IE(1'b0) );
  PDDW1216CDG Pad_IO_dft_sdo_2( .I(wire_dft_sdo_2), .DS(1'b0), .OEN(1'b0), .PAD(dft_sdo_2), .C(),  .PE(1'b0), .IE(1'b0) );

endmodule
