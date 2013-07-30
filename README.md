This is a simple app to test the attitude estimation of the IMU in iOS devices. It displays a floating dice with OpenGL over the video from the rear camera. The dice rotates as if it is being captured by the camera, so the user can explore it by moving the phone around.

Check [this blog post](http://uavster.com/blog/Attitude-estimation-on-iPhone) for more details.

**NOTE**: If opencv2.framework is not found when compiling, you will have to add it manually. Remove opencv2.framework from the Frameworks list (it will have a red icon) under SingleViewTest in the Navigator window. Then, select SingleViewTest in the Navigator window and choose SingleViewTest under Targets. Find the "Link Binary With Libraries" list under the "Build Phases" tab. Click the plus button under the list and, in the window that appears, click "Add Other..."; you will see a file browser. Find the opencv2.framework folder in the folder where you compiled OpenCV, select it and click Open. Try rebuilding the project. Everything should go well now.

**3rd party contributions**

Dice texture: http://www.geminoidi.com
