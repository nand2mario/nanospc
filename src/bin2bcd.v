
// 2 decimal digit binary to BCD converter
// https://www.realdigital.org/doc/6dae6583570fd816d1d675b93578203d

module bin2bcd(
   input [6:0] bin,
   output reg [7:0] bcd
);

integer i;
	
always @(bin) begin
    bcd = 0;		 	
    for (i=0; i<7; i=i+1) begin			// Iterate once for each bit in input number
        if (bcd[3:0] >= 5)
            bcd[3:0] = bcd[3:0] + 3;    // If any BCD digit is >= 5, add three
        if (bcd[7:4] >= 5)
            bcd[7:4] = bcd[7:4] + 3;
        bcd = {bcd[6:0], bin[6-i]};     // Shift one bit, and shift in proper bit from input 
    end
end
endmodule