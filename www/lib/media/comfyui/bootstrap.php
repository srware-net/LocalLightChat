<?php
declare(strict_types=1);

require_once __DIR__ . '/WorkflowGraph.php';
require_once __DIR__ . '/BindingPlan.php';
require_once __DIR__ . '/BindingExecutor.php';
require_once __DIR__ . '/Client.php';
require_once __DIR__ . '/WebSocketClient.php';
require_once __DIR__ . '/Profile.php';
require_once __DIR__ . '/Runner.php';
require_once __DIR__ . '/Adapters/AdapterInterface.php';
require_once __DIR__ . '/Adapters/AdapterSupport.php';
require_once __DIR__ . '/Adapters/HiDreamO1Adapter.php';
require_once __DIR__ . '/Adapters/FireRedImageEditAdapter.php';
require_once __DIR__ . '/Adapters/MageFlowEditAdapter.php';
require_once __DIR__ . '/Adapters/JoyAIImageEditAdapter.php';
require_once __DIR__ . '/Adapters/BooguImageAdapter.php';
require_once __DIR__ . '/Adapters/Krea2TurboAdapter.php';
require_once __DIR__ . '/Adapters/LensTurboAdapter.php';
require_once __DIR__ . '/Adapters/SDXLTurboAdapter.php';
require_once __DIR__ . '/Adapters/Flux2Adapter.php';
require_once __DIR__ . '/Adapters/ZImageAdapter.php';
require_once __DIR__ . '/Adapters/QwenImage21Adapter.php';
require_once __DIR__ . '/Adapters/ErnieImageAdapter.php';
require_once __DIR__ . '/Adapters/AdapterRegistry.php';
require_once __DIR__ . '/WorkflowAnalyzer.php';
