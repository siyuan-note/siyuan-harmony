#include "../entry/src/main/cpp/include/kernel_startup.h"
#include <cassert>
#include <dirent.h>
#include <iostream>
#include <sys/resource.h>
#include <sys/wait.h>

class TestListener {
public:
    int fd;
    uint16_t port;

    explicit TestListener(bool loopback) : fd(socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0)), port(0) {
        assert(fd >= 0);
        const int reuse = 1;
        assert(setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) == 0);
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(loopback ? INADDR_LOOPBACK : INADDR_ANY);
        assert(bind(fd, reinterpret_cast<const sockaddr *>(&address), sizeof(address)) == 0);
        assert(listen(fd, 1) == 0);
        socklen_t length = sizeof(address);
        assert(getsockname(fd, reinterpret_cast<sockaddr *>(&address), &length) == 0);
        port = ntohs(address.sin_port);
    }

    void closeListener() {
        if (fd >= 0) {
            close(fd);
            fd = -1;
        }
    }

    ~TestListener() { closeListener(); }
};

static int descriptorCount() {
    DIR *directory = opendir("/proc/self/fd");
    assert(directory != nullptr);
    int count = 0;
    while (readdir(directory) != nullptr) {
        count++;
    }
    closedir(directory);
    return count;
}

int main() {
    // 使用独立临时端口验证实际监听冲突，不访问运行中的思源端口。
    for (bool loopback : {false, true}) {
        TestListener listener(loopback);
        const int before = descriptorCount();
        for (int index = 0; index < 100; index++) {
            assert(GetKernelPortError(listener.port) == EADDRINUSE);
        }
        assert(descriptorCount() == before);
        listener.closeListener();
        for (int index = 0; index < 100; index++) {
            assert(GetKernelPortError(listener.port) == 0);
        }
        assert(descriptorCount() == before - 1);
    }

    // 建立并关闭真实连接，确认地址复用不会将已关闭连接误判为仍有监听进程。
    TestListener listener(false);
    const int client = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    assert(client >= 0);
    sockaddr_in peer{};
    peer.sin_family = AF_INET;
    peer.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    peer.sin_port = htons(listener.port);
    assert(connect(client, reinterpret_cast<const sockaddr *>(&peer), sizeof(peer)) == 0);
    const int accepted = accept(listener.fd, nullptr, nullptr);
    assert(accepted >= 0);
    close(accepted);
    close(client);
    listener.closeListener();
    assert(GetKernelPortError(listener.port) == 0);

    // 套接字创建失败必须返回错误，不能将资源耗尽视为端口可用。
    const pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        const rlimit limit{0, 0};
        assert(setrlimit(RLIMIT_NOFILE, &limit) == 0);
        _exit(GetKernelPortError(listener.port) == EMFILE ? 0 : 1);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    std::cout << "kernel startup port tests passed\n";
}
