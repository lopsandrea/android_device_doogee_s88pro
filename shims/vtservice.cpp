/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/*
 * Old entry points for vtservice, the system half of MediaTek's video calls.
 *
 * vtservice and its libraries come from the stock Android 10 system image.
 * Five framework symbols they import have changed signature since; each is
 * defined here under its old mangled name and forwarded to the current API.
 * The library is added to vtservice's DT_NEEDED ahead of everything else, so
 * that these definitions are the ones the linker finds first.
 *
 * Each of those constructors runs in memory the caller allocated with Android
 * 10's idea of the class size, measured in the stock libraries:
 *
 *   Surface              1944 bytes   today 632    built in place
 *   AudioSource           152 bytes   today 152    built in place
 *   GraphicBufferMapper     8 bytes   today   8    unchanged, only lock and
 *                                                  unlock moved
 *   AudioTrack            824 bytes   today 1032   does not fit: a proxy
 *
 * Under the 32-bit ARM C++ ABI a constructor returns this, and the callers
 * here use that return value as the new object, so the constructors below
 * return it too.
 *
 * One more is defined here although its signature never changed:
 * AHandler::deliverMessage(), because the class it belongs to grew under
 * MediaTek's subclasses. See its definition.
 *
 * Last, libsource.so's camera source gets the consumer end of its
 * BufferQueue in Android 10's shape; see "The camera source" below. Those
 * entry points are shared with the rest of the process, and change nothing
 * for any caller but libsource.so.
 */

#define LOG_TAG "libshim_vtservice"

#include <dlfcn.h>
#include <string.h>

#include <atomic>
#include <cstddef>
#include <new>

#include <android/content/AttributionSourceState.h>
#include <binder/Binder.h>
#include <binder/IInterface.h>
#include <gui/BufferItem.h>
#include <gui/BufferQueue.h>
#include <gui/IConsumerListener.h>
#include <gui/IGraphicBufferConsumer.h>
#include <gui/Surface.h>
#include <log/log.h>
#include <media/AudioTrack.h>
#include <media/stagefright/AudioSource.h>
#include <media/stagefright/foundation/AHandler.h>
#include <media/stagefright/foundation/AMessage.h>
#include <ui/Fence.h>
#include <ui/GraphicBuffer.h>
#include <ui/GraphicBufferMapper.h>
#include <utils/String8.h>

using android::AHandler;
using android::AMessage;
using android::AudioSource;
using android::AudioTrack;
using android::BufferItem;
using android::BufferQueue;
using android::ConsumerListener;
using android::Fence;
using android::GraphicBuffer;
using android::GraphicBufferMapper;
using android::IConsumerListener;
using android::IGraphicBufferConsumer;
using android::IGraphicBufferProducer;
using android::Rect;
using android::sp;
using android::status_t;
using android::String16;
using android::String8;
using android::Surface;
using android::wp;

static_assert(sizeof(Surface) <= 1944, "Surface no longer fits the caller's allocation");
static_assert(sizeof(AudioSource) <= 152, "AudioSource no longer fits the caller's allocation");
static_assert(sizeof(GraphicBufferMapper) <= 8, "GraphicBufferMapper grew");

namespace {

// The next definition of a symbol this library also defines, that is the
// real one in the framework library.
template <typename Fn>
Fn next(const char* symbol) {
    Fn fn = reinterpret_cast<Fn>(dlsym(RTLD_NEXT, symbol));
    LOG_ALWAYS_FATAL_IF(fn == nullptr, "%s not found", symbol);
    return fn;
}

/*
 * Android 10's AudioTrack fit in 824 bytes and took a plain function as
 * callback. Today's needs 1032 and takes an IAudioTrackCallback, so it cannot
 * be built where the caller expects it. The caller's block holds this proxy
 * instead, which owns a real AudioTrack and answers the five methods the
 * caller uses (libsink's AudioRenderer: start, write, getPosition, latency,
 * getSampleRate).
 *
 * RefBase is a virtual base here as it is in AudioTrack: the caller finds the
 * reference count through the virtual base offset in the object's vtable,
 * and that offset sits in the same slot only if the shapes match.
 *
 * The forwarders below also receive real AudioTracks, from any other code in
 * the process; the two marker words tell the two apart.
 */
struct TrackProxy : public virtual android::RefBase {
    static constexpr uint32_t kMarker0 = 0x53383850;  // "S88P"
    static constexpr uint32_t kMarker1 = 0x5654534d;  // "VTSM"

    uint32_t marker0 = kMarker0;
    uint32_t marker1 = kMarker1;
    sp<AudioTrack> track;

    static TrackProxy* of(const void* object) {
        auto* proxy = static_cast<TrackProxy*>(const_cast<void*>(object));
        return proxy->marker0 == kMarker0 && proxy->marker1 == kMarker1 ? proxy : nullptr;
    }
};

static_assert(sizeof(TrackProxy) <= 824, "TrackProxy does not fit the caller's allocation");

// onMessageReceived() is protected; naming it through a subclass yields a
// member pointer that can be called on any AHandler.
struct HandlerAccess : public AHandler {
    static void onMessage(AHandler* handler, const sp<AMessage>& msg) {
        auto onMessageReceived = &HandlerAccess::onMessageReceived;
        (handler->*onMessageReceived)(msg);
    }
};

/*
 * The camera source.
 *
 * libsource.so's VTCameraSource is Android 10's SurfaceMediaSource under
 * another name: it owns a BufferQueue, hands the producer end to the camera
 * and pulls frames out of the consumer end. Three classes on that consumer
 * end have changed shape since:
 *
 *   IGraphicBufferConsumer   was an IInterface, so RefBase was a virtual
 *                            base; it is a plain RefBase now, and its vtable
 *                            has new methods in the middle
 *   ConsumerListener         three new methods ahead of onFrameAvailable()
 *   BufferItem               168 bytes then, more now
 *
 * Every call VTCameraSource made on its consumer landed on the wrong method,
 * and the reference count it looked up through the vtable was garbage:
 * vtservice crashed in ~VTCameraSource() at the end of every IMS call, voice
 * ones included.
 *
 * So for libsource.so, createBufferQueue() wraps the consumer in Android 10's
 * interface, the ProxyConsumerListener constructor builds a listener that
 * calls VTCameraSource through Android 10's vtable, and BufferItem is built
 * in Android 10's layout. libgui calls those same entry points itself, so each
 * checks who is calling.
 */

// Whether the code at address belongs to libsource.so.
bool inLibsource(const void* address) {
    static std::atomic<void*> base{nullptr};
    Dl_info info;
    if (dladdr(address, &info) == 0) return false;
    if (void* known = base.load(std::memory_order_relaxed); known != nullptr) {
        return info.dli_fbase == known;
    }
    const char* name = info.dli_fname != nullptr ? strrchr(info.dli_fname, '/') : nullptr;
    if (name == nullptr || strcmp(name, "/libsource.so") != 0) return false;
    base.store(info.dli_fbase, std::memory_order_relaxed);
    return true;
}

// Android 10's BufferItem, laid out as libsource.so has it on its stack. It
// reads the buffer, the fence, the timestamp, the frame number and the slot;
// the members it never touches are only kept as room.
struct Q10BufferItem {
    sp<GraphicBuffer> mGraphicBuffer;
    sp<Fence> mFence;
    alignas(4) uint8_t mFenceTime[8] = {};  // std::shared_ptr<FenceTime>
    Rect mCrop = Rect::INVALID_RECT;
    uint32_t mTransform = 0;
    uint32_t mScalingMode = NATIVE_WINDOW_SCALING_MODE_FREEZE;
    int64_t mTimestamp = 0;
    bool mIsAutoTimestamp = false;
    android_dataspace mDataSpace = HAL_DATASPACE_UNKNOWN;
    alignas(4) uint8_t mHdrMetadata[64] = {};
    uint64_t mFrameNumber = 0;
    int mSlot = BufferItem::INVALID_BUFFER_SLOT;
    bool mIsDroppable = false;
    bool mAcquireCalled = false;
    bool mTransformToDisplayInverse = false;
    alignas(4) uint8_t mSurfaceDamage[20] = {};  // Region
    bool mAutoRefresh = false;
    bool mQueuedBuffer = true;
    bool mIsStale = false;
    int mApi = 0;

    Q10BufferItem& operator=(const BufferItem& item) {
        mGraphicBuffer = item.mGraphicBuffer;
        mFence = item.mFence;
        mCrop = item.mCrop;
        mTransform = item.mTransform;
        mScalingMode = item.mScalingMode;
        mTimestamp = item.mTimestamp;
        mIsAutoTimestamp = item.mIsAutoTimestamp;
        mDataSpace = item.mDataSpace;
        mFrameNumber = item.mFrameNumber;
        mSlot = item.mSlot;
        mIsDroppable = item.mIsDroppable;
        mAcquireCalled = item.mAcquireCalled;
        mTransformToDisplayInverse = item.mTransformToDisplayInverse;
        mAutoRefresh = item.mAutoRefresh;
        mQueuedBuffer = item.mQueuedBuffer;
        mIsStale = item.mIsStale;
        mApi = item.mApi;
        return *this;
    }
};

// The offsets libsource.so reads, from its code.
static_assert(sizeof(Q10BufferItem) == 168, "Q10BufferItem is not Android 10's size");
static_assert(offsetof(Q10BufferItem, mFence) == 4);
static_assert(offsetof(Q10BufferItem, mTimestamp) == 40);
static_assert(offsetof(Q10BufferItem, mFrameNumber) == 120);
static_assert(offsetof(Q10BufferItem, mSlot) == 128);

// Built where libsource.so wanted a BufferQueue::ProxyConsumerListener (a
// 40-byte block): today's listener interface, passing each call on to
// VTCameraSource through Android 10's ConsumerListener vtable. The frame
// callbacks hand on today's BufferItem; VTCameraSource ignores it.
class Q10ListenerProxy : public IConsumerListener {
  public:
    explicit Q10ListenerProxy(const wp<ConsumerListener>& listener) : mListener(listener) {}

    void onDisconnect() override { call<>(kOnDisconnect); }
    void onFrameAvailable(const BufferItem& item) override {
        call<const BufferItem*>(kOnFrameAvailable, &item);
    }
    void onFrameReplaced(const BufferItem& item) override {
        call<const BufferItem*>(kOnFrameReplaced, &item);
    }
    void onBuffersReleased() override { call<>(kOnBuffersReleased); }
    void onSidebandStreamChanged() override { call<>(kOnSidebandStreamChanged); }

  private:
    // Android 10's ConsumerListener vtable, after the two destructors.
    enum : size_t {
        kOnDisconnect = 2,
        kOnFrameAvailable,
        kOnFrameReplaced,
        kOnBuffersReleased,
        kOnSidebandStreamChanged,
    };

    template <typename... Args>
    void call(size_t slot, Args... args) {
        sp<ConsumerListener> listener = mListener.promote();
        if (listener == nullptr) return;
        using Method = void (*)(ConsumerListener*, Args...);
        Method const* vtable = *reinterpret_cast<Method* const*>(listener.get());
        vtable[slot](listener.get(), args...);
    }

    const wp<ConsumerListener> mListener;
};

static_assert(sizeof(Q10ListenerProxy) <= 40, "Q10ListenerProxy does not fit the caller's block");

// Handed to libsource.so as its IGraphicBufferConsumer: Android 10's
// interface over today's consumer. Being an IInterface, it has RefBase as a
// virtual base as libsource.so expects, and its methods follow IInterface's
// in Android 10's order. libsource.so calls slots 4 to 17; the rest are there
// so that a stray call still lands on the method it meant.
class Q10GraphicBufferConsumer : public android::IInterface {
  public:
    explicit Q10GraphicBufferConsumer(const sp<IGraphicBufferConsumer>& consumer)
        : mConsumer(consumer) {}

    // From DECLARE_META_INTERFACE, ahead of the interface's own methods.
    virtual const String16& getInterfaceDescriptor() const {
        static const String16 descriptor(u"android.gui.IGraphicBufferConsumer");
        return descriptor;
    }

    virtual status_t acquireBuffer(Q10BufferItem* buffer, nsecs_t presentWhen,
                                   uint64_t maxFrameNumber) {
        BufferItem item;
        status_t err = mConsumer->acquireBuffer(&item, presentWhen, maxFrameNumber);
        if (err == android::OK) *buffer = item;
        return err;
    }
    virtual status_t detachBuffer(int slot) { return mConsumer->detachBuffer(slot); }
    virtual status_t attachBuffer(int* outSlot, const sp<GraphicBuffer>& buffer) {
        return mConsumer->attachBuffer(outSlot, buffer);
    }
    // The EGL display and sync were never anything but "none" here.
    virtual status_t releaseBuffer(int buf, uint64_t frameNumber, void* /* display */,
                                   void* /* fence */, const sp<Fence>& releaseFence) {
        return mConsumer->releaseBuffer(buf, frameNumber, releaseFence);
    }
    virtual status_t consumerConnect(const sp<IConsumerListener>& consumer,
                                     bool controlledByApp) {
        return mConsumer->consumerConnect(consumer, controlledByApp);
    }
    virtual status_t consumerDisconnect() { return mConsumer->consumerDisconnect(); }
    virtual status_t getReleasedBuffers(uint64_t* slotMask) {
        return mConsumer->getReleasedBuffers(slotMask);
    }
    virtual status_t setDefaultBufferSize(uint32_t width, uint32_t height) {
        return mConsumer->setDefaultBufferSize(width, height);
    }
    virtual status_t setMaxBufferCount(int bufferCount) {
        return mConsumer->setMaxBufferCount(bufferCount);
    }
    virtual status_t setMaxAcquiredBufferCount(int maxAcquiredBuffers) {
        return mConsumer->setMaxAcquiredBufferCount(maxAcquiredBuffers);
    }
    virtual status_t setConsumerName(const String8& name) {
        return mConsumer->setConsumerName(name);
    }
    virtual status_t setDefaultBufferFormat(android::PixelFormat format) {
        return mConsumer->setDefaultBufferFormat(format);
    }
    virtual status_t setDefaultBufferDataSpace(android_dataspace dataSpace) {
        return mConsumer->setDefaultBufferDataSpace(dataSpace);
    }
    virtual status_t setConsumerUsageBits(uint64_t usage) {
        return mConsumer->setConsumerUsageBits(usage);
    }
    virtual status_t setConsumerIsProtected(bool isProtected) {
        return mConsumer->setConsumerIsProtected(isProtected);
    }
    virtual status_t setTransformHint(uint32_t hint) { return mConsumer->setTransformHint(hint); }
    // These two take types that have changed; nothing here asks for them.
    virtual status_t getSidebandStream(void* /* outStream */) const {
        return android::INVALID_OPERATION;
    }
    virtual status_t getOccupancyHistory(bool /* forceFlush */, void* /* outHistory */) {
        return android::INVALID_OPERATION;
    }
    virtual status_t discardFreeBuffers() { return mConsumer->discardFreeBuffers(); }
    virtual status_t dumpState(const String8& prefix, String8* outResult) const {
        return mConsumer->dumpState(prefix, outResult);
    }

  protected:
    android::IBinder* onAsBinder() override { return nullptr; }

  private:
    const sp<IGraphicBufferConsumer> mConsumer;
};

}  // namespace

extern "C" {

// Surface(const sp<IGraphicBufferProducer>&, bool): the SurfaceControl handle
// was added as a third parameter.
void* _ZN7android7SurfaceC1ERKNS_2spINS_22IGraphicBufferProducerEEEb(
        void* thiz, const sp<IGraphicBufferProducer>& producer, bool controlledByApp) {
    new (thiz) Surface(producer, controlledByApp, nullptr);
    return thiz;
}

// AudioSource(audio_source_t, ...): the legacy constructor kept today takes
// audio attributes instead of the bare source.
void* _ZN7android11AudioSourceC1E14audio_source_tRKNS_8String16Ejjjjii28audio_microphone_direction_tf(
        void* thiz, audio_source_t source, const String16& opPackageName, uint32_t sampleRate,
        uint32_t channels, uint32_t outSampleRate, uid_t uid, pid_t pid,
        audio_port_handle_t selectedDeviceId, audio_microphone_direction_t micDirection,
        float micFieldDimension) {
    audio_attributes_t attributes = AUDIO_ATTRIBUTES_INITIALIZER;
    attributes.source = source;
    new (thiz) AudioSource(&attributes, opPackageName, sampleRate, channels, outSampleRate, uid,
                           pid, selectedDeviceId, micDirection, micFieldDimension);
    return thiz;
}

// GraphicBufferMapper::lock() with bytes per pixel and per stride. Mapper 2.x,
// the only one this vendor has, never reported either; Android 10 answered -1
// for both on it, and so does this.
status_t _ZN7android19GraphicBufferMapper4lockEPK13native_handlejRKNS_4RectEPPvPiS9_(
        GraphicBufferMapper* thiz, buffer_handle_t handle, uint32_t usage, const Rect& bounds,
        void** vaddr, int32_t* outBytesPerPixel, int32_t* outBytesPerStride) {
    if (outBytesPerPixel != nullptr) *outBytesPerPixel = -1;
    if (outBytesPerStride != nullptr) *outBytesPerStride = -1;
    return thiz->lock(handle, usage, bounds, vaddr);
}

// GraphicBufferMapper::unlock() gained an optional release fence.
status_t _ZN7android19GraphicBufferMapper6unlockEPK13native_handle(GraphicBufferMapper* thiz,
                                                                   buffer_handle_t handle) {
    return thiz->unlock(handle);
}

// The AudioTrack constructor with a legacy callback. The only caller passes
// none and writes synchronously; a callback would need translating into an
// IAudioTrackCallback, so it is refused loudly rather than dropped quietly.
void* _ZN7android10AudioTrackC1E19audio_stream_type_tj14audio_format_tjj20audio_output_flags_tPFviPvS4_ES4_i15audio_session_tNS0_13transfer_typeEPK20audio_offload_info_tjiPK18audio_attributes_tbfi(
        void* thiz, audio_stream_type_t streamType, uint32_t sampleRate, audio_format_t format,
        audio_channel_mask_t channelMask, size_t frameCount, audio_output_flags_t flags,
        void (*callback)(int, void*, void*), void* /* user */, int32_t notificationFrames,
        audio_session_t sessionId, AudioTrack::transfer_type transferType,
        const audio_offload_info_t* offloadInfo, uid_t uid, pid_t pid,
        const audio_attributes_t* attributes, bool doNotReconnect, float maxRequiredSpeed,
        audio_port_handle_t selectedDeviceId) {
    auto* proxy = new (thiz) TrackProxy();
    if (callback != nullptr) {
        ALOGE("AudioTrack with a legacy callback is not supported; the track stays empty");
        return thiz;
    }
    // uid and pid -1 mean "the caller", today as in Android 10.
    android::content::AttributionSourceState attribution;
    attribution.uid = static_cast<int32_t>(uid);
    attribution.pid = static_cast<int32_t>(pid);
    attribution.token = sp<android::BBinder>::make();
    proxy->track = sp<AudioTrack>::make(streamType, sampleRate, format, channelMask, frameCount,
                                        flags, nullptr, notificationFrames, sessionId,
                                        transferType, offloadInfo, attribution, attributes,
                                        doNotReconnect, maxRequiredSpeed, selectedDeviceId);
    return thiz;
}

status_t _ZN7android10AudioTrack5startEv(void* thiz) {
    static auto real = next<status_t (*)(void*)>("_ZN7android10AudioTrack5startEv");
    if (TrackProxy* proxy = TrackProxy::of(thiz)) {
        return proxy->track != nullptr ? real(proxy->track.get()) : android::NO_INIT;
    }
    return real(thiz);
}

ssize_t _ZN7android10AudioTrack5writeEPKvjb(void* thiz, const void* buffer, size_t size,
                                            bool blocking) {
    static auto real =
            next<ssize_t (*)(void*, const void*, size_t, bool)>("_ZN7android10AudioTrack5writeEPKvjb");
    if (TrackProxy* proxy = TrackProxy::of(thiz)) {
        return proxy->track != nullptr ? real(proxy->track.get(), buffer, size, blocking)
                                       : android::NO_INIT;
    }
    return real(thiz, buffer, size, blocking);
}

status_t _ZN7android10AudioTrack11getPositionEPj(void* thiz, uint32_t* position) {
    static auto real = next<status_t (*)(void*, uint32_t*)>("_ZN7android10AudioTrack11getPositionEPj");
    if (TrackProxy* proxy = TrackProxy::of(thiz)) {
        return proxy->track != nullptr ? real(proxy->track.get(), position) : android::NO_INIT;
    }
    return real(thiz, position);
}

uint32_t _ZN7android10AudioTrack7latencyEv(void* thiz) {
    static auto real = next<uint32_t (*)(void*)>("_ZN7android10AudioTrack7latencyEv");
    if (TrackProxy* proxy = TrackProxy::of(thiz)) {
        return proxy->track != nullptr ? real(proxy->track.get()) : 0;
    }
    return real(thiz);
}

uint32_t _ZNK7android10AudioTrack13getSampleRateEv(const void* thiz) {
    static auto real = next<uint32_t (*)(const void*)>("_ZNK7android10AudioTrack13getSampleRateEv");
    if (TrackProxy* proxy = TrackProxy::of(thiz)) {
        return proxy->track != nullptr ? real(proxy->track.get()) : 0;
    }
    return real(thiz);
}

/*
 * AHandler::deliverMessage(), which the looper calls for every message.
 *
 * Android 10's AHandler ended 48 bytes in (on 32-bit), and MediaTek's
 * handlers -- the IMCB message dispatcher in libmtk_vt_service, ImsMa and the
 * RTP controller in libimsma, and others -- keep their own fields from there.
 * Today's AHandler has grown past that: a lock at offset 52, and after it the
 * what and start time of the message being delivered, which
 * deliverMessage() takes and writes around each message. On a MediaTek
 * handler the "lock" is one of the handler's own pointers. The looper thread
 * blocks on it at the first message and nothing is delivered after that;
 * in vtservice that included the IMS stack's request for the video codecs, so
 * calls went out offering video with no codec at all, and the network
 * answered 400.
 *
 * AMessage::deliver() reaches this through the PLT, so this definition, found
 * first, replaces the framework's for the whole process. It delivers and does
 * nothing else. What it leaves out is bookkeeping: the message counter, the
 * per-message stats kept when verbose stats are on, and the delivery status
 * that bug reports print. Handlers built for today's layout, such as MediaCodec's,
 * work without it.
 */
void _ZN7android8AHandler14deliverMessageERKNS_2spINS_8AMessageEEE(AHandler* thiz,
                                                                   const sp<AMessage>& msg) {
    HandlerAccess::onMessage(thiz, msg);
}

// The camera source's four entry points; see "The camera source" above.

// BufferQueue::createBufferQueue(): libsource.so's consumer end comes back
// wrapped in Android 10's interface. Its sp holds that interface, which
// Q10GraphicBufferConsumer is.
void _ZN7android11BufferQueue17createBufferQueueEPNS_2spINS_22IGraphicBufferProducerEEEPNS1_INS_22IGraphicBufferConsumerEEEb(
        sp<IGraphicBufferProducer>* outProducer, void* outConsumer, bool consumerIsSurfaceFlinger) {
    static auto real = next<void (*)(sp<IGraphicBufferProducer>*, sp<IGraphicBufferConsumer>*, bool)>(
            "_ZN7android11BufferQueue17createBufferQueueEPNS_2spINS_22IGraphicBufferProducerEEEPNS1_INS_22IGraphicBufferConsumerEEEb");
    if (!inLibsource(__builtin_return_address(0))) {
        real(outProducer, static_cast<sp<IGraphicBufferConsumer>*>(outConsumer),
             consumerIsSurfaceFlinger);
        return;
    }
    sp<IGraphicBufferConsumer> consumer;
    real(outProducer, &consumer, consumerIsSurfaceFlinger);
    *static_cast<sp<Q10GraphicBufferConsumer>*>(outConsumer) =
            consumer != nullptr ? sp<Q10GraphicBufferConsumer>::make(consumer) : nullptr;
}

// BufferQueue::ProxyConsumerListener(const wp<ConsumerListener>&).
void* _ZN7android11BufferQueue21ProxyConsumerListenerC1ERKNS_2wpINS_16ConsumerListenerEEE(
        void* thiz, const wp<ConsumerListener>& listener) {
    static auto real = next<void* (*)(void*, const wp<ConsumerListener>&)>(
            "_ZN7android11BufferQueue21ProxyConsumerListenerC1ERKNS_2wpINS_16ConsumerListenerEEE");
    if (!inLibsource(__builtin_return_address(0))) return real(thiz, listener);
    new (thiz) Q10ListenerProxy(listener);
    return thiz;
}

// BufferItem() and ~BufferItem(). The ARM C++ ABI has destructors return
// this as well.
void* _ZN7android10BufferItemC1Ev(void* thiz) {
    static auto real = next<void* (*)(void*)>("_ZN7android10BufferItemC1Ev");
    if (!inLibsource(__builtin_return_address(0))) return real(thiz);
    new (thiz) Q10BufferItem();
    return thiz;
}

void* _ZN7android10BufferItemD1Ev(void* thiz) {
    static auto real = next<void* (*)(void*)>("_ZN7android10BufferItemD1Ev");
    if (!inLibsource(__builtin_return_address(0))) return real(thiz);
    static_cast<Q10BufferItem*>(thiz)->~Q10BufferItem();
    return thiz;
}

}  // extern "C"
