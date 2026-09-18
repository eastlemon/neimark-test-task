<?php

declare(strict_types=1);

namespace App;

/**
 * Проверка текста на палиндром.
 *
 * Два режима:
 *  - normalized (по умолчанию): регистр, пробелы и знаки препинания игнорируются,
 *    сравниваются только буквы и цифры («А роза упала на лапу Азора» — палиндром);
 *  - strict: посимвольное сравнение строки «как есть».
 *
 * Строка обрабатывается как последовательность символов UTF-8 (mb_*-функции),
 * а не байтов: strrev() здесь неприменим — он переворачивает байты и ломает
 * многобайтовые кодировки.
 *
 * Сложность: O(n) по времени с ранним выходом при первом несовпадении,
 * O(n) дополнительной памяти на посимвольный массив.
 */
final class Palindrome
{
    /**
     * @throws \InvalidArgumentException если $text — невалидный UTF-8
     */
    public static function isPalindrome(string $text, bool $strict = false): bool
    {
        if (!mb_check_encoding($text, 'UTF-8')) {
            throw new \InvalidArgumentException('Text must be valid UTF-8');
        }

        if (!$strict) {
            $text = self::normalize($text);
        }

        // mb_str_split режет строку по СИМВОЛАМ UTF-8, а не по байтам
        $chars = mb_str_split($text, 1, 'UTF-8');

        // два указателя: с начала и с конца
        for ($i = 0, $j = \count($chars) - 1; $i < $j; $i++, $j--) {
            if ($chars[$i] !== $chars[$j]) {
                return false;
            }
        }

        // пустая строка и строка из одного символа — тривиальные палиндромы
        return true;
    }

    private static function normalize(string $text): string
    {
        // регистронезависимость (работает и с кириллицей: «А» -> «а»)
        $text = mb_strtolower($text, 'UTF-8');

        // оставляем буквы и цифры любых алфавитов (Unicode-категории L* и N*),
        // выбрасывая пробелы, пунктуацию и символы
        return (string) preg_replace('/[^\p{L}\p{N}]+/u', '', $text);
    }
}
