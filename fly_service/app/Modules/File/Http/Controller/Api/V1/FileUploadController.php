<?php

declare(strict_types=1);

namespace app\Modules\File\Http\Controller\Api\V1;

use app\Modules\File\Application\FileUploadService;
use app\Modules\File\Http\Request\FileUploadRequest;
use app\response\ApiResponse;
use app\Support\Auth\AuthContextHolder;
use support\Request;
use support\Response;

/**
 * 前端直传 RustFS 接口。
 */
final class FileUploadController
{
    /**
     * 注入上传服务和请求验证器。
     */
    public function __construct(
        private readonly FileUploadService $uploads,
        private readonly FileUploadRequest $validator,
    )
    {
    }

    /**
     * 签发头像上传临时凭证。
     */
    public function credential(Request $request): Response
    {
        $auth = AuthContextHolder::get();
        return ApiResponse::success($this->uploads->createAvatarCredential($auth->userId, $this->validator->credential($request)), 201);
    }

    /**
     * 签发聊天附件上传临时凭证。
     */
    public function messageCredential(Request $request): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success(
            $this->uploads->createMessageCredential(
                $auth->userId,
                $this->validator->messageCredential($request),
            ),
            201,
        );
    }

    /**
     * 确认 RustFS 对象上传完成。
     */
    public function complete(Request $request, string $resource_id): Response
    {
        $auth = AuthContextHolder::get();
        return ApiResponse::success($this->uploads->complete($auth->userId, $this->validator->resourceId($resource_id)));
    }

    /**
     * 批量签发指定Multipart分片的直传凭证。
     */
    public function multipartPartCredentials(Request $request, string $resource_id): Response
    {
        $auth = AuthContextHolder::get();
        $input = $this->validator->multipartParts($request);

        return ApiResponse::success($this->uploads->createPartCredentials(
            $auth->userId,
            $this->validator->resourceId($resource_id),
            $input['upload_id'],
            $input['part_numbers'],
        ));
    }

    /**
     * 查询上传中真实分片或已完成最终资源，用于客户端断点与崩溃恢复。
     */
    public function multipartStatus(Request $request, string $resource_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->uploads->multipartStatus(
            $auth->userId,
            $this->validator->resourceId($resource_id),
        ));
    }

    /**
     * 校验分片ETag并完成S3对象合并。
     */
    public function multipartComplete(Request $request, string $resource_id): Response
    {
        $auth = AuthContextHolder::get();
        $input = $this->validator->multipartComplete($request);

        return ApiResponse::success($this->uploads->completeMultipart(
            $auth->userId,
            $this->validator->resourceId($resource_id),
            $input['upload_id'],
            $input['parts'],
        ));
    }

    /**
     * 取消Multipart会话并释放对象存储分片。
     */
    public function multipartAbort(Request $request, string $resource_id): Response
    {
        $auth = AuthContextHolder::get();

        return ApiResponse::success($this->uploads->abortMultipart(
            $auth->userId,
            $this->validator->resourceId($resource_id),
            $this->validator->uploadId($request->post('upload_id')),
        ));
    }
}
