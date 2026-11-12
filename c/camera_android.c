/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
 * SPDX-License-Identifier: AGPL-3.0-only
 *
 * The camera of Android, through the NDK's camera API: frames of grayscale, the luma of the back
 * camera's YUV, turned upright, for `Camera.Native` (Camera/Native.lean). camera_v4l2.c is the
 * same for Linux desktop.
 *
 * The NDK's camera and media libraries are loaded when the camera is first opened, so that Paw's
 * Android build, which links only the libraries every app needs, links this file unchanged.
 */

#ifdef __ANDROID__

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <camera/NdkCameraCaptureSession.h>
#include <camera/NdkCameraDevice.h>
#include <camera/NdkCameraManager.h>
#include <camera/NdkCameraMetadata.h>
#include <camera/NdkCaptureRequest.h>
#include <media/NdkImage.h>
#include <media/NdkImageReader.h>

#include <lean/lean.h>

#define FNS(X)                                                                                     \
  X(camera, ACameraManager_create)                                                                 \
  X(camera, ACameraManager_delete)                                                                 \
  X(camera, ACameraManager_getCameraIdList)                                                        \
  X(camera, ACameraManager_deleteCameraIdList)                                                     \
  X(camera, ACameraManager_getCameraCharacteristics)                                               \
  X(camera, ACameraManager_openCamera)                                                             \
  X(camera, ACameraMetadata_getConstEntry)                                                         \
  X(camera, ACameraMetadata_free)                                                                  \
  X(camera, ACameraDevice_close)                                                                   \
  X(camera, ACameraDevice_createCaptureRequest)                                                    \
  X(camera, ACameraDevice_createCaptureSession)                                                    \
  X(camera, ACaptureRequest_free)                                                                  \
  X(camera, ACaptureRequest_addTarget)                                                             \
  X(camera, ACaptureRequest_setEntry_u8)                                                           \
  X(camera, ACameraOutputTarget_create)                                                            \
  X(camera, ACameraOutputTarget_free)                                                              \
  X(camera, ACaptureSessionOutputContainer_create)                                                 \
  X(camera, ACaptureSessionOutputContainer_free)                                                   \
  X(camera, ACaptureSessionOutputContainer_add)                                                    \
  X(camera, ACaptureSessionOutput_create)                                                          \
  X(camera, ACaptureSessionOutput_free)                                                            \
  X(camera, ACameraCaptureSession_setRepeatingRequest)                                             \
  X(camera, ACameraCaptureSession_stopRepeating)                                                   \
  X(camera, ACameraCaptureSession_close)                                                           \
  X(media, AImageReader_new)                                                                       \
  X(media, AImageReader_delete)                                                                    \
  X(media, AImageReader_getWindow)                                                                 \
  X(media, AImageReader_acquireLatestImage)                                                        \
  X(media, AImage_delete)                                                                          \
  X(media, AImage_getWidth)                                                                        \
  X(media, AImage_getHeight)                                                                       \
  X(media, AImage_getPlaneData)                                                                    \
  X(media, AImage_getPlaneRowStride)                                                               \
  X(media, AImage_getPlanePixelStride)

#define DECLARE(lib, f) static __typeof__(f) *p_##f;
FNS(DECLARE)

static int loaded = 0;

/* Loads the NDK's libraries; NULL once they are, else why not. */
static const char *load(void) {
  if (loaded) return NULL;
  void *camera = dlopen("libcamera2ndk.so", RTLD_NOW | RTLD_LOCAL);
  void *media = dlopen("libmediandk.so", RTLD_NOW | RTLD_LOCAL);
  if (camera == NULL || media == NULL) return "this Android has no camera library";
#define RESOLVE(lib, f)                                                                            \
  if ((p_##f = (__typeof__(f) *)dlsym(lib, #f)) == NULL) return "this Android lacks " #f;
  FNS(RESOLVE)
  loaded = 1;
  return NULL;
}

typedef struct {
  ACameraManager *manager;
  ACameraDevice *device;
  AImageReader *reader;
  ANativeWindow *window;
  ACameraOutputTarget *target;
  ACaptureRequest *request;
  ACaptureSessionOutput *output;
  ACaptureSessionOutputContainer *outputs;
  ACameraCaptureSession *session;
  ACameraDevice_StateCallbacks callbacks;
  int32_t rotation;
  volatile int broken;
  int open;
} cam;

static void cam_close(cam *c) {
  if (!c->open) return;
  if (c->session) {
    p_ACameraCaptureSession_stopRepeating(c->session);
    p_ACameraCaptureSession_close(c->session);
  }
  if (c->request) p_ACaptureRequest_free(c->request);
  if (c->target) p_ACameraOutputTarget_free(c->target);
  if (c->outputs) p_ACaptureSessionOutputContainer_free(c->outputs);
  if (c->output) p_ACaptureSessionOutput_free(c->output);
  if (c->device) p_ACameraDevice_close(c->device);
  if (c->reader) p_AImageReader_delete(c->reader);
  if (c->manager) p_ACameraManager_delete(c->manager);
  memset(c, 0, sizeof *c);
}

static void cam_finalize(void *p) {
  cam_close(p);
  free(p);
}

static void cam_foreach(void *p, b_lean_obj_arg f) {
  (void)p;
  (void)f;
}

static lean_external_class *cam_class = NULL;

static lean_obj_res fail(const char *why) {
  char buf[256];
  snprintf(buf, sizeof buf, "camera: %s", why);
  return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(buf)));
}

static void on_disconnected(void *ctx, ACameraDevice *d) {
  (void)d;
  ((cam *)ctx)->broken = 1;
}

static void on_error(void *ctx, ACameraDevice *d, int e) {
  (void)d;
  (void)e;
  ((cam *)ctx)->broken = 1;
}

static void on_session(void *ctx, ACameraCaptureSession *s) {
  (void)ctx;
  (void)s;
}

/* The back camera's id, or the first's, and how far its picture is turned, in degrees. */
static const char *pick(ACameraManager *m, ACameraIdList *ids, int32_t *rotation) {
  const char *chosen = NULL;
  for (int i = 0; i < ids->numCameras; i++) {
    ACameraMetadata *meta = NULL;
    if (p_ACameraManager_getCameraCharacteristics(m, ids->cameraIds[i], &meta) != ACAMERA_OK) continue;
    ACameraMetadata_const_entry facing, orientation;
    int back = p_ACameraMetadata_getConstEntry(meta, ACAMERA_LENS_FACING, &facing) == ACAMERA_OK &&
               facing.count > 0 && facing.data.u8[0] == ACAMERA_LENS_FACING_BACK;
    if (chosen == NULL || back) {
      chosen = ids->cameraIds[i];
      *rotation = 0;
      if (p_ACameraMetadata_getConstEntry(meta, ACAMERA_SENSOR_ORIENTATION, &orientation) == ACAMERA_OK &&
          orientation.count > 0)
        *rotation = orientation.data.i32[0];
    }
    p_ACameraMetadata_free(meta);
    if (back) break;
  }
  return chosen;
}

/* Opens the back camera at `w` × `h` and starts it; `dev` is Linux's, and unused here. */
lean_obj_res frank_camera_open(b_lean_obj_arg dev, uint32_t w, uint32_t h) {
  (void)dev;
  const char *why = load();
  if (why != NULL) return fail(why);
  if (cam_class == NULL) cam_class = lean_register_external_class(cam_finalize, cam_foreach);
  cam *c = calloc(1, sizeof *c);
  if (c == NULL) return fail("out of memory");
  c->open = 1;
  c->callbacks.context = c;
  c->callbacks.onDisconnected = on_disconnected;
  c->callbacks.onError = on_error;
  ACameraCaptureSession_stateCallbacks session_cbs = {
      .context = c, .onClosed = on_session, .onReady = on_session, .onActive = on_session};
  ACameraIdList *ids = NULL;
  c->manager = p_ACameraManager_create();
  if (c->manager == NULL || p_ACameraManager_getCameraIdList(c->manager, &ids) != ACAMERA_OK) {
    why = "the camera service cannot be reached";
    goto out;
  }
  const char *id = pick(c->manager, ids, &c->rotation);
  if (id == NULL) {
    why = "this device has no camera";
    goto out;
  }
  camera_status_t s = p_ACameraManager_openCamera(c->manager, id, &c->callbacks, &c->device);
  if (s == ACAMERA_ERROR_PERMISSION_DENIED) {
    why = "not allowed";
    goto out;
  }
  if (s != ACAMERA_OK) {
    why = "the camera cannot be opened; another app may be using it";
    goto out;
  }
  if (p_AImageReader_new((int32_t)w, (int32_t)h, AIMAGE_FORMAT_YUV_420_888, 3, &c->reader) != AMEDIA_OK ||
      p_AImageReader_getWindow(c->reader, &c->window) != AMEDIA_OK) {
    why = "the camera's frames cannot be read";
    goto out;
  }
  // Continuous autofocus, for a code held close.
  uint8_t af = ACAMERA_CONTROL_AF_MODE_CONTINUOUS_PICTURE;
  if (p_ACameraDevice_createCaptureRequest(c->device, TEMPLATE_PREVIEW, &c->request) != ACAMERA_OK ||
      p_ACameraOutputTarget_create(c->window, &c->target) != ACAMERA_OK ||
      p_ACaptureRequest_addTarget(c->request, c->target) != ACAMERA_OK ||
      p_ACaptureSessionOutputContainer_create(&c->outputs) != ACAMERA_OK ||
      p_ACaptureSessionOutput_create(c->window, &c->output) != ACAMERA_OK ||
      p_ACaptureSessionOutputContainer_add(c->outputs, c->output) != ACAMERA_OK) {
    why = "the camera cannot be set up";
    goto out;
  }
  p_ACaptureRequest_setEntry_u8(c->request, ACAMERA_CONTROL_AF_MODE, 1, &af);
  if (p_ACameraDevice_createCaptureSession(c->device, c->outputs, &session_cbs, &c->session) != ACAMERA_OK ||
      p_ACameraCaptureSession_setRepeatingRequest(c->session, NULL, 1, &c->request, NULL) != ACAMERA_OK) {
    why = "the camera cannot be started";
    goto out;
  }
out:
  if (ids != NULL) p_ACameraManager_deleteCameraIdList(ids);
  if (why != NULL) {
    cam_finalize(c);
    return fail(why);
  }
  return lean_io_result_mk_ok(lean_alloc_external(cam_class, c));
}

/* The luma plane `src`, `w` × `h`, turned clockwise by `rotation` degrees into `dst`. */
static void upright(const uint8_t *src, int32_t stride, int32_t step, int32_t w, int32_t h, int32_t rotation,
                    uint8_t *dst) {
  for (int32_t y = 0; y < h; y++) {
    const uint8_t *row = src + (size_t)y * stride;
    for (int32_t x = 0; x < w; x++) {
      uint8_t v = row[(size_t)x * step];
      size_t i;
      switch (rotation) {
      case 90: i = (size_t)x * h + (h - 1 - y); break;
      case 180: i = (size_t)(h - 1 - y) * w + (w - 1 - x); break;
      case 270: i = (size_t)(w - 1 - x) * h + y; break;
      default: i = (size_t)y * w + x; break;
      }
      dst[i] = v;
    }
  }
}

/* The newest frame since the last, waiting up to `ms` for one: none if none came. */
lean_obj_res frank_camera_next(b_lean_obj_arg handle, uint32_t ms) {
  cam *c = lean_get_external_data(handle);
  if (!c->open) return fail("stopped");
  AImage *img = NULL;
  for (uint32_t waited = 0;; waited += 10) {
    if (c->broken) return fail("the camera went away");
    media_status_t s = p_AImageReader_acquireLatestImage(c->reader, &img);
    if (s == AMEDIA_OK) break;
    if (s != AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE) return fail("a frame cannot be read");
    if (waited >= ms) return lean_io_result_mk_ok(lean_box(0));
    struct timespec t = {0, 10 * 1000 * 1000};
    nanosleep(&t, NULL);
  }
  int32_t w = 0, h = 0, stride = 0, step = 0, len = 0;
  uint8_t *data = NULL;
  if (p_AImage_getWidth(img, &w) != AMEDIA_OK || p_AImage_getHeight(img, &h) != AMEDIA_OK ||
      p_AImage_getPlaneRowStride(img, 0, &stride) != AMEDIA_OK ||
      p_AImage_getPlanePixelStride(img, 0, &step) != AMEDIA_OK ||
      p_AImage_getPlaneData(img, 0, &data, &len) != AMEDIA_OK || w <= 0 || h <= 0 || step <= 0 ||
      (size_t)(h - 1) * stride + (size_t)(w - 1) * step + 1 > (size_t)len) {
    p_AImage_delete(img);
    return fail("a frame smaller than its format");
  }
  size_t size = (size_t)w * h;
  lean_object *a = lean_alloc_sarray(1, size, size);
  int32_t r = c->rotation % 360;
  upright(data, stride, step, w, h, r, lean_sarray_cptr(a));
  p_AImage_delete(img);
  uint32_t ow = (r == 90 || r == 270) ? (uint32_t)h : (uint32_t)w;
  uint32_t oh = (r == 90 || r == 270) ? (uint32_t)w : (uint32_t)h;
  lean_object *wh = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(wh, 0, lean_box_uint32(oh));
  lean_ctor_set(wh, 1, a);
  lean_object *frame = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(frame, 0, lean_box_uint32(ow));
  lean_ctor_set(frame, 1, wh);
  lean_object *some = lean_alloc_ctor(1, 1, 0);
  lean_ctor_set(some, 0, frame);
  return lean_io_result_mk_ok(some);
}

/* Stops the camera and lets it go; the handle reads no more frames. */
lean_obj_res frank_camera_close(b_lean_obj_arg handle) {
  cam_close(lean_get_external_data(handle));
  return lean_io_result_mk_ok(lean_box(0));
}

#endif
