typedef enum bit [1:0] {
    RK4_CMD_LOAD_PROG = 2'b00,
    RK4_CMD_RUN       = 2'b01,
    RK4_CMD_RAW_BYTES = 2'b10
} rk4_cmd_t;

class rk4_seq_item extends uvm_sequence_item;

    rand rk4_cmd_t  cmd_type;
    rand bit [7:0]  payload[];

    constraint c_load_prog_size {
        cmd_type == RK4_CMD_LOAD_PROG -> payload.size() == 32;
    }

    constraint c_run_size {
        cmd_type == RK4_CMD_RUN -> payload.size() == 4;
    }

    `uvm_object_utils_begin(rk4_seq_item)
        `uvm_field_enum(rk4_cmd_t, cmd_type, UVM_DEFAULT)
        `uvm_field_array_int(payload, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "rk4_seq_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        string s;
        s = $sformatf("cmd=%s  payload[%0d]={", cmd_type.name(), payload.size());
        foreach (payload[i]) begin
            if (i != 0) s = {s, ", "};
            s = {s, $sformatf("0x%02h", payload[i])};
        end
        s = {s, "}"};
        return s;
    endfunction

endclass
