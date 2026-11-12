/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
 * SPDX-License-Identifier: AGPL-3.0-only
 *
 * The camera of Linux desktop, through V4L2: frames of grayscale, the luma of what the device
 * streams, for `Camera.Native` (Camera/Native.lean). camera_android.c is the same for Android.
 */

#if defined(__linux__) && !defined(__ANDROID__)

#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <lean/lean.h>

#define NBUF 4

typedef struct {
  int fd;
  uint32_t width, height, stride, fourcc;
  int nbuf;
  void *start[NBUF];
  size_t length[NBUF];
  int streaming;
} cam;

static void cam_close(cam *c) {
  if (c->fd < 0) return;
  if (c->streaming) {
    enum v4l2_buf_type t = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    ioctl(c->fd, VIDIOC_STREAMOFF, &t);
    c->streaming = 0;
  }
  for (int i = 0; i < c->nbuf; i++)
    if (c->start[i] != MAP_FAILED && c->start[i] != NULL) munmap(c->start[i], c->length[i]);
  c->nbuf = 0;
  close(c->fd);
  c->fd = -1;
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

static lean_obj_res fail(const char *what, const char *why) {
  char buf[512];
  snprintf(buf, sizeof buf, "%s: %s", what, why);
  return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(buf)));
}

static int xioctl(int fd, unsigned long req, void *arg) {
  int r;
  do r = ioctl(fd, req, arg);
  while (r == -1 && errno == EINTR);
  return r;
}

/* The formats whose luma is read here, best first: from these the grayscale costs one copy. */
static const uint32_t formats[] = {V4L2_PIX_FMT_GREY,   V4L2_PIX_FMT_YUYV,   V4L2_PIX_FMT_UYVY,
                                   V4L2_PIX_FMT_NV12,   V4L2_PIX_FMT_NV21,   V4L2_PIX_FMT_YUV420,
                                   V4L2_PIX_FMT_YVU420};
#define NFORMATS (sizeof formats / sizeof formats[0])

static int rank(uint32_t f) {
  for (unsigned i = 0; i < NFORMATS; i++)
    if (formats[i] == f) return (int)i;
  return -1;
}

/* Bytes from one luma sample to the next along a row, and the first one's offset. */
static void luma_step(uint32_t fourcc, uint32_t *step, uint32_t *offset) {
  *step = (fourcc == V4L2_PIX_FMT_YUYV || fourcc == V4L2_PIX_FMT_UYVY) ? 2 : 1;
  *offset = fourcc == V4L2_PIX_FMT_UYVY ? 1 : 0;
}

/* Opens the device at `dev`, asking for `w` × `h`, and starts it streaming. */
lean_obj_res frank_camera_open(b_lean_obj_arg dev, uint32_t w, uint32_t h) {
  if (cam_class == NULL) cam_class = lean_register_external_class(cam_finalize, cam_foreach);
  const char *path = lean_string_cstr(dev);
  int fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) return fail(path, strerror(errno));
  cam *c = calloc(1, sizeof *c);
  if (c == NULL) {
    close(fd);
    return fail(path, "out of memory");
  }
  c->fd = fd;
  const char *why = NULL;
  char whybuf[128];
  struct v4l2_capability cap;
  memset(&cap, 0, sizeof cap);
  if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
    why = "not a V4L2 device";
    goto out;
  }
  uint32_t caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS) ? cap.device_caps : cap.capabilities;
  if (!(caps & V4L2_CAP_VIDEO_CAPTURE)) {
    why = "not a camera";
    goto out;
  }
  if (!(caps & V4L2_CAP_STREAMING)) {
    why = "the camera cannot stream";
    goto out;
  }
  int best = -1;
  struct v4l2_fmtdesc d;
  memset(&d, 0, sizeof d);
  d.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  for (d.index = 0; xioctl(fd, VIDIOC_ENUM_FMT, &d) == 0; d.index++) {
    int r = rank(d.pixelformat);
    if (r >= 0 && (best < 0 || r < best)) best = r;
  }
  // shortcut: no JPEG decoder, so a camera that only gives MJPEG is not read; add one if needed.
  if (best < 0) {
    why = "the camera gives no format frank_chat reads (grayscale, YUYV, UYVY, NV12 or YUV 4:2:0)";
    goto out;
  }
  struct v4l2_format f;
  memset(&f, 0, sizeof f);
  f.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  f.fmt.pix.width = w;
  f.fmt.pix.height = h;
  f.fmt.pix.pixelformat = formats[best];
  f.fmt.pix.field = V4L2_FIELD_NONE;
  if (xioctl(fd, VIDIOC_S_FMT, &f) < 0) {
    // Some devices, such as a loopback, only have the format their writer set.
    if (xioctl(fd, VIDIOC_G_FMT, &f) < 0) {
      snprintf(whybuf, sizeof whybuf, "setting the format: %s", strerror(errno));
      why = whybuf;
      goto out;
    }
  }
  c->width = f.fmt.pix.width;
  c->height = f.fmt.pix.height;
  c->fourcc = f.fmt.pix.pixelformat;
  uint32_t step, offset;
  luma_step(c->fourcc, &step, &offset);
  c->stride = f.fmt.pix.bytesperline ? f.fmt.pix.bytesperline : c->width * step;
  if (rank(c->fourcc) < 0 || c->width == 0 || c->height == 0 || c->stride < c->width * step) {
    why = "the camera gives frames frank_chat cannot read";
    goto out;
  }
  struct v4l2_requestbuffers req;
  memset(&req, 0, sizeof req);
  req.count = NBUF;
  req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  req.memory = V4L2_MEMORY_MMAP;
  if (xioctl(fd, VIDIOC_REQBUFS, &req) < 0 || req.count == 0) {
    why = "the camera gives no buffers";
    goto out;
  }
  c->nbuf = req.count < NBUF ? (int)req.count : NBUF;
  for (int i = 0; i < c->nbuf; i++) c->start[i] = MAP_FAILED;
  for (int i = 0; i < c->nbuf; i++) {
    struct v4l2_buffer b;
    memset(&b, 0, sizeof b);
    b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    b.memory = V4L2_MEMORY_MMAP;
    b.index = i;
    if (xioctl(fd, VIDIOC_QUERYBUF, &b) < 0) {
      why = "the camera's buffers cannot be read";
      goto out;
    }
    c->length[i] = b.length;
    c->start[i] = mmap(NULL, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, b.m.offset);
    if (c->start[i] == MAP_FAILED) {
      why = "the camera's buffers cannot be mapped";
      goto out;
    }
    if (xioctl(fd, VIDIOC_QBUF, &b) < 0) {
      why = "the camera's buffers cannot be queued";
      goto out;
    }
  }
  enum v4l2_buf_type t = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (xioctl(fd, VIDIOC_STREAMON, &t) < 0) {
    snprintf(whybuf, sizeof whybuf, "starting the camera: %s", strerror(errno));
    why = whybuf;
    goto out;
  }
  c->streaming = 1;
out:
  if (why != NULL) {
    lean_obj_res r = fail(path, why);
    cam_finalize(c);
    return r;
  }
  return lean_io_result_mk_ok(lean_alloc_external(cam_class, c));
}

static void requeue(cam *c, struct v4l2_buffer *b) { xioctl(c->fd, VIDIOC_QBUF, b); }

/* The newest frame since the last, waiting up to `ms` for one, as its luma: none if none came. */
lean_obj_res frank_camera_next(b_lean_obj_arg h, uint32_t ms) {
  cam *c = lean_get_external_data(h);
  if (c->fd < 0) return fail("camera", "stopped");
  struct pollfd p = {.fd = c->fd, .events = POLLIN};
  int n = poll(&p, 1, (int)ms);
  if (n < 0 && errno != EINTR) return fail("camera", strerror(errno));
  if (n <= 0) return lean_io_result_mk_ok(lean_box(0));
  if (p.revents & (POLLERR | POLLHUP | POLLNVAL)) return fail("camera", "the device went away");
  // Only the newest of the frames waiting is read; the others go back at once.
  struct v4l2_buffer got;
  int have = 0;
  for (;;) {
    struct v4l2_buffer b;
    memset(&b, 0, sizeof b);
    b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    b.memory = V4L2_MEMORY_MMAP;
    if (xioctl(c->fd, VIDIOC_DQBUF, &b) < 0) {
      if (errno == EAGAIN) break;
      if (have) requeue(c, &got);
      return fail("camera", strerror(errno));
    }
    if (have) requeue(c, &got);
    got = b;
    have = 1;
  }
  if (!have) return lean_io_result_mk_ok(lean_box(0));
  uint32_t step, offset;
  luma_step(c->fourcc, &step, &offset);
  size_t need = (size_t)(c->height - 1) * c->stride + (size_t)(c->width - 1) * step + offset + 1;
  if (got.index >= (uint32_t)c->nbuf || need > c->length[got.index]) {
    requeue(c, &got);
    return fail("camera", "a frame smaller than its format");
  }
  size_t size = (size_t)c->width * c->height;
  lean_object *a = lean_alloc_sarray(1, size, size);
  uint8_t *dst = lean_sarray_cptr(a);
  const uint8_t *src = c->start[got.index];
  for (uint32_t y = 0; y < c->height; y++) {
    const uint8_t *row = src + (size_t)y * c->stride + offset;
    if (step == 1)
      memcpy(dst + (size_t)y * c->width, row, c->width);
    else
      for (uint32_t x = 0; x < c->width; x++) dst[(size_t)y * c->width + x] = row[(size_t)x * step];
  }
  requeue(c, &got);
  lean_object *wh = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(wh, 0, lean_box_uint32(c->height));
  lean_ctor_set(wh, 1, a);
  lean_object *frame = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(frame, 0, lean_box_uint32(c->width));
  lean_ctor_set(frame, 1, wh);
  lean_object *some = lean_alloc_ctor(1, 1, 0);
  lean_ctor_set(some, 0, frame);
  return lean_io_result_mk_ok(some);
}

/* Stops the camera and lets the device go; the handle reads no more frames. */
lean_obj_res frank_camera_close(b_lean_obj_arg h) {
  cam_close(lean_get_external_data(h));
  return lean_io_result_mk_ok(lean_box(0));
}

#endif
