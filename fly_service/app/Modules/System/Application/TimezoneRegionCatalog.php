<?php

declare(strict_types=1);

namespace app\Modules\System\Application;

use RuntimeException;

/** 从项目维护的中文地区文件提供时区目录，禁止依赖 PHP 内置时区列表生成运营选项。 */
final class TimezoneRegionCatalog
{
    /** 注入时区与电话地区 JSON 文件绝对路径。 */
    public function __construct(private readonly string $filePath) {}

    /**
     * 返回 JSON 中的全部地区数据。
     *
     * @return list<array{region_code:string,region_cn:string,region_en:string,flag_emoji:string,svg_file:string,timezones:list<string>}>
     */
    public function regions(): array
    {
        $content = @file_get_contents($this->filePath);
        if ($content === false) {
            throw new RuntimeException('时区地区数据文件无法读取');
        }
        $regions = json_decode($content, true, 512, JSON_THROW_ON_ERROR);
        if (!is_array($regions)) {
            throw new RuntimeException('时区地区数据格式不正确');
        }
        foreach ($regions as $region) {
            if (!is_array($region)
                || !is_string($region['region_code'] ?? null)
                || !is_string($region['region_cn'] ?? null)
                || !is_string($region['region_en'] ?? null)
                || !is_string($region['flag_emoji'] ?? null)
                || !is_string($region['svg_file'] ?? null)
                || !is_array($region['timezones'] ?? null)
                || array_filter($region['timezones'], static fn (mixed $timezone): bool => !is_string($timezone) || $timezone === '') !== []) {
                throw new RuntimeException('时区地区数据包含无效记录');
            }
        }
        /** @var list<array{region_code:string,region_cn:string,region_en:string,flag_emoji:string,svg_file:string,timezones:list<string>}> $regions */
        return array_values($regions);
    }

    /**
     * 将地区文件展开为管理端下拉框可直接消费的时区选项。
     *
     * @return list<array{timezone:string,region_code:string,region_cn:string,region_en:string,flag_emoji:string}>
     */
    public function timezones(): array
    {
        $timezones = [];
        foreach ($this->regions() as $region) {
            foreach ($region['timezones'] as $timezone) {
                $timezones[] = [
                    'timezone' => $timezone,
                    'region_code' => $region['region_code'],
                    'region_cn' => $region['region_cn'],
                    'region_en' => $region['region_en'],
                    'flag_emoji' => $region['flag_emoji'],
                ];
            }
        }

        usort($timezones, static fn (array $left, array $right): int => $left['timezone'] <=> $right['timezone']);

        return $timezones;
    }

    /** 判断时区是否存在于项目维护的地区文件中。 */
    public function contains(string $timezone): bool
    {
        foreach ($this->timezones() as $option) {
            if ($option['timezone'] === $timezone) return true;
        }
        return false;
    }
}
