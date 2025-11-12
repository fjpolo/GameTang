
# Original GAMETANK Gamepad Setup

GAMETang since 0.9(check with @nand2mario) supports Original GAMETANK Gamepads, also supporting 8BitDo gamepads.

## No Level-Shifter

This setup was tested using an [8BitDo N30 2.4g wireless gamepad for original GAMETANK](https://www.8bitdo.com/n30-wireless-for-original-gametank/). After some testing, this controller setup does not require a 3V3<->5V level shifter and can be directly connected to the FPGA IOs.

### Requirements

- An original GAMETANK Gamepad
- Wires

### Wiring diagram

<img src="images/GAMETANKGamepad_wiring.png" width=400>


## Level-Shifter

In some cases, although not tested, probably cases such as original GAMETANK/Famicom controllers, TTL5V signals might be needed for correct functionality. In this case, a LVCMOS3V3<->TTL5V level shifter is needed.

### Requirements

- An original GAMETANK Gamepad
- Wires
- [4 Channels IIC I2C Logic Level Shifter Bi-Directional Module](https://www.aliexpress.com/item/1005004225321778.html?spm=a2g0o.order_list.order_list_main.27.22111802nFvcM9)
    - This is needed because GAMETang has Low Voltage CMOS 3.3V signals and GAMETANK Gamepad uses 5V TTL logic.

### Wiring diagram

<img src="images/GAMETANKGamepad_wiring_levelShifter.png" width=400>

## GAMETANK to FamiCom

There's a way to convert 2 GAMETANK joysticks to FamiCom input connector:

<img src="images/GAMETANKGamepad_GAMETANK2FamiCom.jpg" width=400>
