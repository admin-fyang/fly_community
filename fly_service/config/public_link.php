<?php

declare(strict_types=1);

return [
    'base_url' => rtrim((string)(getenv('PUBLIC_LINK_BASE_URL') ?: getenv('APP_URL') ?: ''), '/'),
];
