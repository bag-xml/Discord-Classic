#include <Foundation/Foundation.h>

@interface  NSDictionary (Indexing)
- (id)objectForKeyedSubscript:(id)key;
@end

@interface  NSMutableDictionary (Indexing)
- (void)setObject:(id)obj forKeyedSubscript:(id)key;
@end