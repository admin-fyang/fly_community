<?php

namespace app\controller;

use support\Request;

class IndexController
{
    /**
     * 返回Webman默认欢迎页面。
     */
    public function index(Request $request)
    {
        return '你好';
    }

    /**
     * 返回示例模板页面。
     */
    public function view(Request $request)
    {
        return view('index/view', ['name' => 'webman']);
    }

    /**
     * 返回示例JSON响应。
     */
    public function json(Request $request)
    {
        return json(['code' => 0, 'msg' => 'ok']);
    }

}
