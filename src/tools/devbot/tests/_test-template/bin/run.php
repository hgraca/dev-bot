#!/usr/bin/env php
<?php

declare(strict_types=1);

require_once dirname(__DIR__) . '/vendor/autoload.php';

$pokeList = array_slice($argv, 1);

$out = [];
foreach ($pokeList as $pokeName) {
    $json = stream_get_contents(fopen("https://pokeapi.co/api/v2/pokemon/$pokeName", 'r'));
    $pokeData = json_decode($json, true);
    $givenPokeExperience = (int) $pokeData['base_experience'];
    $json = stream_get_contents(fopen("https://pokeapi.co/api/v2/pokemon/$pokeName", 'r'));
    $pokeData = json_decode($json, true);
    $url = $pokeData['species']['url'];
    $json = stream_get_contents(fopen($url, 'r'));
    $dataArray = json_decode($json, true);
    $growthRateUrl = $dataArray['growth_rate']['url'];
    $json = stream_get_contents(fopen($growthRateUrl, 'r'));
    $dataArray = json_decode($json, true);
    $levelList = $dataArray['levels'];
    $possibleLevel = 0;
    $pokeLevel = $possibleLevel;
    foreach ($levelList as ['experience' => $levelExperience, 'level' => $level]) {
        if ($givenPokeExperience < $levelExperience) {
            $pokeLevel = $possibleLevel;
            break;
        }
        $possibleLevel = $level;
    }
    $json = stream_get_contents(fopen("https://pokeapi.co/api/v2/pokemon/$pokeName", 'r'));
    $pokeData = json_decode($json, true);
    $pokeExperience = (int) $pokeData['base_experience'];
    $json = stream_get_contents(fopen("https://pokeapi.co/api/v2/pokemon/$pokeName", 'r'));
    $pokeData = json_decode($json, true);
    $out[] = $pokeData['name']
        . ' ' . $pokeExperience
        . ' ' . $pokeData['species']['name']
        . ' ' . $pokeLevel;
}

echo implode("\n", $out);
