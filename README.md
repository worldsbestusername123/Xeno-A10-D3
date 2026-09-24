# Xeno A10-D3
An AI accelerator I made because I didn't want to study for my exams<br>
<br>
Written in SystemVerilog<br>
<br>
Artix 7-100t 676 -2 C<br>
<br>
It has a 1x384 vector architecture (INT8)<br>
It uses a ping pong kinda buffer with 24 BRAM Banks<br>
I like men<br>
It's built for the Artix 7 100t 676 BGA -2<br>
How did I fit 384 MAC units in 240 DSP slices? I just fed one weight two activations (I couldn't do two activations cuz the DSP slices were 25x18)<br>
I hate two's complement math<br>
runs on 300 mhz, more info here<br>
<img width="951" height="175" alt="image" src="https://github.com/user-attachments/assets/6aab1366-c5e4-4670-aec8-4e36b4dbcb25" /><br>
<br>
here's the power requirement<br>
<img width="666" height="182" alt="image" src="https://github.com/user-attachments/assets/6e8d6a7a-0b88-46c3-95df-c966dfd331c0" /><br>
<br>
This is all implemented btw, also it has been testbenched and works, where's the testbench code? ~~It's in my ass! I lost it no shit.~~<br>
I found it, I'll link it when I finish my homework
<br>
<img width="506" height="158" alt="image" src="https://github.com/user-attachments/assets/9f102de8-5c12-4e32-b6e2-31932e955cd0" /><br>
^<br>
|<br>
this is the utilization
