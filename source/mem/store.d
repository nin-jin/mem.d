module mem.store;

/** What is Atom stores */
enum Store : ubyte
{
    /** Store normal value */
    value = 'V',

    /** Store error info */
    error = 'E',
}