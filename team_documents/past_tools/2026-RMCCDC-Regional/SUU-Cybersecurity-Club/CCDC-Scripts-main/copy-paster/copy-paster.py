import pyautogui
import tkinter
import time

# Count down
for i in range(5):
    print(5 - i)
    time.sleep(1)


clipboard_content = tkinter.Tk().clipboard_get()

pyautogui.write(clipboard_content, interval=0.01)