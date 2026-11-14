`timescale 1ns/1ps

`include "cerbero_defs.svh"

`ifndef CERBERO_ROT_SECRET
  `define CERBERO_ROT_SECRET 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210
`endif

module tb_nova_rtl;

  localparam int MAX_CYCLES = 20000;
  localparam int DMEM_WORDS = 16384;
  localparam int OUT_COUNT_WORD = 'h3000 / 4;
  localparam int OUT_BUFFER_WORD = 'h3004 / 4;
  localparam int OUT_BUFFER_CAPACITY = ('h4000 - 'h3004) / 4;
`ifdef CERBERO_MAX_CYCLES
  localparam int NOVA_MAX_CYCLES = `CERBERO_MAX_CYCLES;
`else
  localparam int NOVA_MAX_CYCLES = MAX_CYCLES;
`endif

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;
  logic halted;
  logic [`XLEN-1:0] psw;
  logic [`NREGS-1:0][`XLEN-1:0] regs;
  logic [31:0] perf_ciclos;
  logic [31:0] perf_instrucciones;
  integer expected;
  integer cycles;
  integer output_count;
  integer output_index;
  integer dmem_dump_index;
  integer dmem_dump_file;
  string expected_out;
  string actual_out;
  string dmem_dump_path;
  bit check_expected_out;
  bit check_expected_return;
  bit dump_dmem;

  top #(.ROT_SECRET(`CERBERO_ROT_SECRET)) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (halted),
      .psw      (psw),
      .dbg_regs (regs),
      .perf_ciclos (perf_ciclos),
      .perf_instrucciones (perf_instrucciones)
  );

  initial begin
    if (!$value$plusargs("EXPECTED=%d", expected)) expected = 25;
    expected_out = "";
    check_expected_out = $test$plusargs("EXPECTED_OUT=");
    check_expected_return = !$test$plusargs("OMITIR_VERIFICACION_RETORNO");
    dmem_dump_path = "";
    dump_dmem = $value$plusargs("DMEM_DUMP=%s", dmem_dump_path);
    if (check_expected_out)
      $value$plusargs("EXPECTED_OUT=%s", expected_out);

    $display("=== ejecutable Nova sobre el RTL CERBERO ===");
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    cycles = 0;
    while (!halted && cycles < NOVA_MAX_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    repeat (8) @(posedge clk);
    #1;

    if (!halted)
      $fatal(1, "el procesador no se detuvo tras %0d ciclos (PC=0x%08h, R14=0x%08h, R15=0x%08h)",
             cycles, dut.if_pc, regs[14], regs[15]);
    $display("  ciclos: %0d", cycles);
    $display("  ciclos RTL: %0d", perf_ciclos);
    $display("  instrucciones RTL: %0d", perf_instrucciones);
    $display("  retorno R6: %0d (0x%08h)", regs[6], regs[6]);
    output_count = dut.u_dmem.storage[OUT_COUNT_WORD];
    if ($isunknown(output_count) || output_count < 0 ||
        output_count > OUT_BUFFER_CAPACITY)
      $fatal(1, "contador de salida invalido en DMEM: %0d", output_count);
    $display("  salida en DMEM del procesador (%0d valores):", output_count);
    actual_out = "";
    for (output_index = 0; output_index < output_count; output_index = output_index + 1) begin
      if (output_index != 0) actual_out = {actual_out, ","};
      actual_out = {actual_out,
                    $sformatf("%0d",
                              $signed(dut.u_dmem.storage[OUT_BUFFER_WORD + output_index]))};
      $display("    [%0d] %0d (0x%08h)", output_index,
               $signed(dut.u_dmem.storage[OUT_BUFFER_WORD + output_index]),
               dut.u_dmem.storage[OUT_BUFFER_WORD + output_index]);
    end
    if (check_expected_out && actual_out != expected_out)
      $fatal(1, "salida incorrecta: esperado [%s], obtenido [%s]",
             expected_out, actual_out);
    if (check_expected_return && regs[6] !== expected)
      $fatal(1, "retorno incorrecto: esperado %0d, obtenido %0d", expected, regs[6]);
    if (psw[`PSW_EXC] !== 1'b0)
      $fatal(1, "el procesador registro una excepcion, PSW=0x%08h", psw);
    if (psw[`PSW_AUTH] !== 1'b0)
      $fatal(1, "la sesion de la boveda no se cerro, PSW=0x%08h", psw);
    if (psw[`PSW_AUTHFAIL] !== 1'b0)
      $fatal(1, "fallo la autenticacion, PSW=0x%08h", psw);

    if (dump_dmem) begin
      dmem_dump_file = $fopen(dmem_dump_path, "w");
      if (dmem_dump_file == 0)
        $fatal(1, "no se pudo abrir el volcado DMEM: %s", dmem_dump_path);
      for (dmem_dump_index = 0; dmem_dump_index < DMEM_WORDS;
           dmem_dump_index = dmem_dump_index + 1)
        $fdisplay(dmem_dump_file, "%04h %08h", dmem_dump_index * 4,
                  dut.u_dmem.storage[dmem_dump_index]);
      $fclose(dmem_dump_file);
    end

    $display("RESULTADO: OK");
    $finish;
  end

endmodule
