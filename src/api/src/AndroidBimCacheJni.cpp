#include "RuntimeSceneCache.hpp"

#include <jni.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace {

using tbe::api::BimCacheSceneDTO;

struct NativeBimCacheHandle {
    BimCacheSceneDTO scene{};
    std::vector<std::int64_t> primitive_data{};
    std::vector<double> primitive_bounds{};
};

thread_local std::string last_error{};

std::string to_string(JNIEnv* environment, jstring value) {
    if (value == nullptr) return {};
    const char* utf8 = environment->GetStringUTFChars(value, nullptr);
    if (utf8 == nullptr) return {};
    std::string result(utf8);
    environment->ReleaseStringUTFChars(value, utf8);
    return result;
}

NativeBimCacheHandle* to_handle(jlong value) {
    return reinterpret_cast<NativeBimCacheHandle*>(static_cast<std::uintptr_t>(value));
}

jlong to_jlong(NativeBimCacheHandle* value) {
    return static_cast<jlong>(reinterpret_cast<std::uintptr_t>(value));
}

jlongArray make_long_array(JNIEnv* environment, const std::vector<std::int64_t>& values) {
    auto* result = environment->NewLongArray(static_cast<jsize>(values.size()));
    if (result != nullptr && !values.empty()) {
        environment->SetLongArrayRegion(
            result,
            0,
            static_cast<jsize>(values.size()),
            reinterpret_cast<const jlong*>(values.data())
        );
    }
    return result;
}

jdoubleArray make_bounds_array(JNIEnv* environment, const tbe::api::AABB3D& bounds) {
    constexpr jsize count = 6;
    const jdouble values[count]{
        bounds.min.x, bounds.min.y, bounds.min.z,
        bounds.max.x, bounds.max.y, bounds.max.z,
    };
    auto* result = environment->NewDoubleArray(count);
    if (result != nullptr) environment->SetDoubleArrayRegion(result, 0, count, values);
    return result;
}

} // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeOpen(
    JNIEnv* environment,
    jclass,
    jstring cache_path,
    jstring source_ifc_path
) {
    try {
        const auto cache = to_string(environment, cache_path);
        const auto source = to_string(environment, source_ifc_path);
        if (cache.empty() || source.empty()) {
            last_error = "BIM cache and IFC source paths are required";
            return 0;
        }
        auto handle = std::make_unique<NativeBimCacheHandle>();
        handle->scene = tbe::api::runtime_cache::read_file(cache, source);
        for (const auto& chunk : handle->scene.chunks) {
            for (const auto& primitive : chunk.primitives) {
                handle->primitive_data.push_back(static_cast<std::int64_t>(primitive.element_id.value));
                handle->primitive_data.push_back(static_cast<std::int64_t>(primitive.kind));
                handle->primitive_data.push_back(static_cast<std::int64_t>(primitive.revision));
                handle->primitive_data.push_back(static_cast<std::int64_t>(chunk.level_id.value));
                const auto& bounds = primitive.bounds;
                handle->primitive_bounds.insert(handle->primitive_bounds.end(), {
                    bounds.min.x, bounds.min.y, bounds.min.z,
                    bounds.max.x, bounds.max.y, bounds.max.z,
                });
            }
        }
        last_error.clear();
        return to_jlong(handle.release());
    } catch (const std::exception& error) {
        last_error = error.what();
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeClose(
    JNIEnv*,
    jclass,
    jlong handle
) {
    delete to_handle(handle);
}

JNIEXPORT jstring JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeLastError(JNIEnv* environment, jclass) {
    return environment->NewStringUTF(last_error.c_str());
}

JNIEXPORT jint JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkCount(JNIEnv*, jclass, jlong handle) {
    const auto* cache = to_handle(handle);
    return cache == nullptr ? 0 : static_cast<jint>(cache->scene.chunks.size());
}

JNIEXPORT jlong JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkLevelId(JNIEnv*, jclass, jlong handle, jint chunk_index) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->scene.chunks.size()) return 0;
    return static_cast<jlong>(cache->scene.chunks[static_cast<std::size_t>(chunk_index)].level_id.value);
}

JNIEXPORT jstring JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkMaterial(
    JNIEnv* environment,
    jclass,
    jlong handle,
    jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->scene.chunks.size()) {
        return environment->NewStringUTF("generic");
    }
    return environment->NewStringUTF(
        cache->scene.chunks[static_cast<std::size_t>(chunk_index)].material_category.c_str()
    );
}

JNIEXPORT jdoubleArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkBounds(
    JNIEnv* environment,
    jclass,
    jlong handle,
    jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->scene.chunks.size()) return nullptr;
    return make_bounds_array(environment, cache->scene.chunks[static_cast<std::size_t>(chunk_index)].bounds);
}

JNIEXPORT jobject JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkPositions(
    JNIEnv* environment,
    jclass,
    jlong handle,
    jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->scene.chunks.size()) return nullptr;
    const auto& positions = cache->scene.chunks[static_cast<std::size_t>(chunk_index)].positions;
    if (positions.empty()) return nullptr;
    return environment->NewDirectByteBuffer(
        const_cast<float*>(positions.data()),
        static_cast<jlong>(positions.size() * sizeof(float))
    );
}

JNIEXPORT jobject JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkIndices(
    JNIEnv* environment,
    jclass,
    jlong handle,
    jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->scene.chunks.size()) return nullptr;
    const auto& indices = cache->scene.chunks[static_cast<std::size_t>(chunk_index)].indices;
    if (indices.empty()) return nullptr;
    return environment->NewDirectByteBuffer(
        const_cast<std::uint32_t*>(indices.data()),
        static_cast<jlong>(indices.size() * sizeof(std::uint32_t))
    );
}

JNIEXPORT jlongArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativePrimitiveData(JNIEnv* environment, jclass, jlong handle) {
    const auto* cache = to_handle(handle);
    return cache == nullptr ? nullptr : make_long_array(environment, cache->primitive_data);
}

JNIEXPORT jdoubleArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativePrimitiveBounds(JNIEnv* environment, jclass, jlong handle) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr) return nullptr;
    auto* result = environment->NewDoubleArray(static_cast<jsize>(cache->primitive_bounds.size()));
    if (result != nullptr && !cache->primitive_bounds.empty()) {
        environment->SetDoubleArrayRegion(
            result,
            0,
            static_cast<jsize>(cache->primitive_bounds.size()),
            cache->primitive_bounds.data()
        );
    }
    return result;
}

} // extern "C"
