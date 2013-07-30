//
//  GLViewController.m
//  MotionTest
//
//  Created by uavster on 7/23/13.
//  Copyright (c) 2013 uavster. All rights reserved.
//

#import "GLViewController.h"
#import <CoreMotion/CoreMotion.h>

using namespace cv;

@interface GLViewController() {
    Mat camFrameTex, camFrameDstROI;
    GLuint bgTex;
    int bgTexWidth, bgTexHeight;    // Background texture dimensions
    int camWidth, camHeight;        // Camera frame dimesions
    int vpWidth, vpHeight;          // Viewport dimensions
    GLKTextureInfo *texInfo;
}
@property (nonatomic, strong) EAGLContext *context;
@property (nonatomic, strong) IBOutlet UILabel *debugLabel;
@property (nonatomic, strong) CMMotionManager *motion;
@property (nonatomic, strong) CvVideoCamera *camera;
@property (nonatomic, strong) NSObject *syncLastFrame;
@end

@implementation GLViewController

-(void)viewDidLoad {
    static const float fps = 30.0f;
    
    @try {

        self.debugLabel.hidden = YES;
        
        self.syncLastFrame = [NSObject alloc];
    
        vpWidth = self.view.bounds.size.width * self.view.contentScaleFactor;
        vpHeight = self.view.bounds.size.height * self.view.contentScaleFactor;

        // Start capturing from camera
        self.camera = [[CvVideoCamera alloc] init];
        self.camera.delegate = self;
            self.camera.defaultAVCaptureDevicePosition = AVCaptureDevicePositionBack;
        self.camera.defaultAVCaptureSessionPreset = AVCaptureSessionPreset640x480;
        self.camera.defaultAVCaptureVideoOrientation = AVCaptureVideoOrientationPortrait;
        self.camera.defaultFPS = 30;
        self.camera.grayscaleMode = NO;
        [self.camera start];
    
        // Crop one of the camera frame dimensions, so aspect ratio is equal to the viewport's
        camWidth = self.camera.imageHeight; // Swapped dimensions because of portrait mode
        camHeight = self.camera.imageWidth;
        float camAspect = camWidth / (float)camHeight;
        float vpAspect = vpWidth / (float)vpHeight;
        if (camAspect > vpAspect) {
            // Crop width
            camWidth = camHeight * vpAspect;
        } else if (camAspect < vpAspect) {
            // Crop height
            camHeight = camWidth / vpAspect;
        }
    
        // Background texture dimensions must be powers of two while larger than the frame dimensions
        bgTexWidth = pow(2, ceil(log2(camWidth)));
        bgTexHeight = pow(2, ceil(log2(camHeight)));

        // Instantiate motion manager
        self.motion = [[CMMotionManager alloc] init];
        if (self.motion.isDeviceMotionAvailable) {
            self.motion.deviceMotionUpdateInterval = 1.0 / fps;
            [self.motion startDeviceMotionUpdatesUsingReferenceFrame: CMAttitudeReferenceFrameXArbitraryCorrectedZVertical];
        } else {
            self.debugLabel.hidden = NO;
            [self.debugLabel setText:@"Device motion is not available in your device"];
        }
    
        // Create GL context
        self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        if (self.context == nil) @throw [NSException exceptionWithName:@"Load error" reason:@"Failed to create ES context" userInfo:nil];
    
        // Set GL current context
        [EAGLContext setCurrentContext:self.context];
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glClearColor(0.0, 0.0, 0.0, 1.0);
    
        // Tell the view about the GL context
        GLKView *view = (GLKView *)self.view;
        view.context = self.context;
    
        // Create texture for camera frames
        glEnable(GL_TEXTURE_2D);
        glGenTextures(1, &bgTex);
        glBindTexture(GL_TEXTURE_2D, bgTex);
        glTexImage2D(GL_TEXTURE_2D, 0, 4, bgTexWidth, bgTexHeight, 0, GL_BGRA, GL_UNSIGNED_BYTE, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
        // Load texture
        NSLog(@"GL Error = %u", glGetError()); // Solves error on Apple's implementation of OpenGL
        NSString *texFileName = [[NSBundle mainBundle] pathForResource:@"dice_tex" ofType:@"jpg"];
        if (texFileName == nil) @throw [NSException exceptionWithName:@"Load error" reason:@"Unable to find path for texture image" userInfo:nil];
        NSError *texLoadError;
        self->texInfo = [GLKTextureLoader textureWithContentsOfFile:texFileName options:nil error:&texLoadError];
        if (self->texInfo == nil) @throw [NSException exceptionWithName:@"Load error" reason:[NSString stringWithFormat:@"Texture error: %@", texLoadError.localizedDescription] userInfo:nil];

        // GL render configuration
        view.drawableMultisample = GLKViewDrawableMultisampleNone;
        self.preferredFramesPerSecond = fps;
        
    } @catch(NSException *e) {
        [self.debugLabel setText:e.reason];
        self.debugLabel.hidden = NO;
        NSLog(@"Error: %@", e.reason);
    }
}

-(void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    static double time = 0;
    time += (double)self.timeSinceLastDraw;
    
    glViewport(0, 0, vpWidth, vpHeight);
    
    // Set image from camera as background
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
    glDisable(GL_CULL_FACE);
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(GLKMatrix4MakeOrtho(0, 1, 1, 0, -1, 1).m);
    glMatrixMode(GL_TEXTURE);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
        
    glDisable(GL_LIGHTING);
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, bgTex);
    @synchronized(self.syncLastFrame) {
        if (!camFrameTex.empty()) {
            // glTexSubImage2D does not work!! Some people reported the same problem, but couldn't find why it happens. Had to use glTexImage2D instead. Tested on iPhone 4S.
            // glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, bgTexWidth, bgTexHeight, GL_RGB, GL_UNSIGNED_BYTE, camFrameTex.data);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, bgTexWidth, bgTexHeight, 0, GL_BGRA, GL_UNSIGNED_BYTE, camFrameTex.data);
        }
    }
    const static GLfloat backgroundVertices[] = { 0, 0, 1, 0, 1, 1, 0, 1 };
    float maxTexX = camWidth / (float)bgTexWidth;
    float maxTexY = camHeight / (float)bgTexHeight;
    GLfloat backgroundTexCoords[] = { 0, 0, maxTexX, 0, maxTexX, maxTexY, 0, maxTexY };
    const static GLubyte backgroundIndices[] = { 0, 1, 2, 2, 3, 0 };
    glColor4f(1, 1, 1, 1);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_VERTEX_ARRAY);
    glVertexPointer(2, GL_FLOAT, 0, backgroundVertices);
    glTexCoordPointer(2, GL_FLOAT, 0, backgroundTexCoords);
    glDrawElements(GL_TRIANGLES, sizeof(backgroundIndices) / sizeof(backgroundIndices[0]), GL_UNSIGNED_BYTE, backgroundIndices);
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
        
    glDisable(GL_TEXTURE_2D);
    glEnable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    
    glClear(GL_DEPTH_BUFFER_BIT);
    
    float vpAspect = fabsf(vpWidth / (float)vpHeight);
    GLKMatrix4 perspective = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(60.0f), vpAspect, 0.1f, 100.0f);
    
    GLKMatrix4 modelView;
    
    if (self.motion.isDeviceMotionAvailable) {
        CMDeviceMotion *devMotion = self.motion.deviceMotion;
        CMRotationMatrix r = devMotion.attitude.rotationMatrix;
        // All matrices are specified in column-major order
        // r.mXY is the element in colum X and row Y
        modelView = GLKMatrix4Make(
                                    r.m11, r.m21, r.m31, 0.0f,
                                    r.m12, r.m22, r.m32, 0.0f,
                                    r.m13, r.m23, r.m33, 0.0f,
                                    0.0f, 0.0f, -4.0f, 1.0f
                                    );
   
     } else {
        float camDistToCenter = 2.5;
        float camPeriod = 4.0;
        float camZAmp = 2.0;
        float camZPeriod = 4.0;
        float camX = camDistToCenter * sin(2 * M_PI / camPeriod * time);
        float camY = camDistToCenter * cos(2 * M_PI / camPeriod * time);
        float camZ = camZAmp * sin(2 * M_PI / camZPeriod * time);
        modelView = GLKMatrix4MakeLookAt(camX, camY, camZ, 0, 0, 0, 0, 0, 1);
    }
    
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(perspective.m);
    
    glMatrixMode(GL_MODELVIEW);
    glLoadMatrixf(modelView.m);
    
    glEnable(GL_DEPTH_TEST);

    [self renderObject];
}

-(void)renderObject {
    glDisable(GL_LIGHTING);
    
    const static GLfloat vertices[] = {
        -0.5, -0.5, 0.5, -0.5, -0.5, -0.5, 0.5, -0.5, -0.5, 0.5, -0.5, 0.5,
        -0.5, 0.5, 0.5, -0.5, 0.5, -0.5, 0.5, 0.5, -0.5, 0.5, 0.5, 0.5,
        -0.5, -0.5, 0.5, 0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5, 0.5, 0.5,
        -0.5, -0.5, -0.5, 0.5, -0.5, -0.5, 0.5, 0.5, -0.5, -0.5, 0.5, -0.5,
        -0.5, 0.5, 0.5, -0.5, 0.5, -0.5, -0.5, -0.5, -0.5, -0.5, -0.5, 0.5,
        0.5, 0.5, 0.5, 0.5, 0.5, -0.5, 0.5, -0.5, -0.5, 0.5, -0.5, 0.5,
    };
    const static GLubyte indices[] = {
        0, 1, 2, 2, 3, 0,
        4, 7, 6, 6, 5, 4,
        8, 9, 10, 10, 11, 8,
        12, 15, 14, 14, 13, 12,
        16, 17, 18, 18, 19, 16,
        20, 23, 22, 22, 21, 20,
    };
    const static GLfloat colors[] = {
        1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 0, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1 };
    const static float incr = 341.0 / 1024.0;
    const static GLfloat texCoords[] = {
        incr, 0, incr, incr, 2*incr, incr, 2*incr, 0,   // 1
        incr, 3*incr, incr, 2*incr, 2*incr, 2*incr, 2*incr, 3*incr, // 6
        incr, 2*incr, 0, 2*incr, 0, 3*incr, incr, 3*incr,   // 4
        incr, incr, 2*incr, incr, 2*incr, 2*incr, incr, 2*incr,  // 3
        0, 2*incr, incr, 2*incr, incr, incr, 0, incr,   // 2
        3*incr, 2*incr, 2*incr, 2*incr, 2*incr, incr, 3*incr, incr, // 5
    };
    
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    
    // Upload geometry and texture coordinates
    if (self->texInfo != nil) {
        glEnable(self->texInfo.target);
        glBindTexture(self->texInfo.target, self->texInfo.name);
        glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    }
    else {
        glEnableClientState(GL_COLOR_ARRAY);
    }
    glEnableClientState(GL_VERTEX_ARRAY);
    
    glVertexPointer(3, GL_FLOAT, 0, vertices);
    if (self->texInfo != nil) glTexCoordPointer(2, GL_FLOAT, 0, texCoords);
    else glColorPointer(4, GL_FLOAT, 0, colors);
    glDrawElements(GL_TRIANGLES, sizeof(indices) / sizeof(indices[0]), GL_UNSIGNED_BYTE, indices);
    
    if (self->texInfo != nil) {
        glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    } else {
        glDisableClientState(GL_COLOR_ARRAY);
    }
    glDisableClientState(GL_VERTEX_ARRAY);
}

-(void)processImage:(cv::Mat &)image {
    @synchronized(self.syncLastFrame) {
        if (camFrameTex.empty()) {
            // Create background image with the full texture size, but with a ROI to copy only the rectangle containing the frame
            camFrameTex.create(bgTexHeight, bgTexWidth, CV_8UC4);
            camFrameDstROI = camFrameTex(cv::Rect(0, 0, camWidth, camHeight));
        }
        // Copy the camera frame to the background image
        Mat camFrameSrcROI = image(cv::Rect((image.cols - camFrameDstROI.cols) / 2, (image.rows - camFrameDstROI.rows) / 2, camFrameDstROI.cols, camFrameDstROI.rows));
        camFrameSrcROI.copyTo(camFrameDstROI);
    }
}

@end
