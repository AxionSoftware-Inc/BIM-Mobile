#pragma once

#include <condition_variable>
#include <cstddef>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <queue>
#include <thread>
#include <type_traits>
#include <vector>

namespace tbe::core {

class JobSystem {
public:
    explicit JobSystem(std::size_t worker_count = std::thread::hardware_concurrency());
    ~JobSystem();

    JobSystem(const JobSystem&) = delete;
    JobSystem& operator=(const JobSystem&) = delete;

    template <typename Fn>
    auto submit(Fn&& fn) -> std::future<std::invoke_result_t<Fn>>;

    [[nodiscard]] std::size_t worker_count() const noexcept;

private:
    void worker_loop();

    mutable std::mutex mutex_;
    std::condition_variable wake_;
    std::queue<std::function<void()>> jobs_;
    std::vector<std::thread> workers_;
    bool stopping_{false};
};

template <typename Fn>
auto JobSystem::submit(Fn&& fn) -> std::future<std::invoke_result_t<Fn>> {
    using Result = std::invoke_result_t<Fn>;

    auto task = std::make_shared<std::packaged_task<Result()>>(std::forward<Fn>(fn));
    auto result = task->get_future();

    {
        std::lock_guard lock(mutex_);
        jobs_.push([task]() {
            (*task)();
        });
    }

    wake_.notify_one();
    return result;
}

} // namespace tbe::core
