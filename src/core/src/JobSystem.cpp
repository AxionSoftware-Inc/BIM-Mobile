#include "tbe/core/JobSystem.hpp"

#include <algorithm>

namespace tbe::core {

JobSystem::JobSystem(std::size_t worker_count) {
    const auto safe_worker_count = std::max<std::size_t>(1, worker_count);
    workers_.reserve(safe_worker_count);

    for (std::size_t index = 0; index < safe_worker_count; ++index) {
        workers_.emplace_back([this]() {
            worker_loop();
        });
    }
}

JobSystem::~JobSystem() {
    {
        std::lock_guard lock(mutex_);
        stopping_ = true;
    }

    wake_.notify_all();

    for (auto& worker : workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
}

std::size_t JobSystem::worker_count() const noexcept {
    return workers_.size();
}

void JobSystem::worker_loop() {
    while (true) {
        std::function<void()> job;

        {
            std::unique_lock lock(mutex_);
            wake_.wait(lock, [this]() {
                return stopping_ || !jobs_.empty();
            });

            if (stopping_ && jobs_.empty()) {
                return;
            }

            job = std::move(jobs_.front());
            jobs_.pop();
        }

        job();
    }
}

} // namespace tbe::core

