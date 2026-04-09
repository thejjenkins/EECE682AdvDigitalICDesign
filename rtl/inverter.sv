module inverter (
  input  logic test_in,
  output logic test_out
  );
  
  assign test_out = ~test_in;
endmodule

