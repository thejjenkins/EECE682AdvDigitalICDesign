import serial

def main():
    # Open COM port (8 data bits, no parity, 1 stop bit = 8N1)
    ser = serial.Serial(
        port="COM18",
        baudrate=115200
    )

    try:
        ser.write(bytes([0xAA]))
    finally:
        ser.close()

if __name__ == "__main__":
    main()